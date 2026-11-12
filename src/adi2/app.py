"""ADI-2 Control — native GTK4/libadwaita remote for RME ADI-2 DAC/Pro.

Talks to the hardware over USB-MIDI SysEx (RME's published protocol)
through ALSA `amidi`. With no device attached it runs fully offline as
an EQ/profile builder: every control still edits state and profiles,
and Apply writes SysEx to a file instead of the unit.
"""
from __future__ import annotations
import json
import math
import os
import threading
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk, Gdk, Pango  # noqa: E402

from . import params as P  # noqa: E402
from . import protocol as proto  # noqa: E402
from .eq import Band, EqProfile  # noqa: E402
from .transport import Transport, find_ports  # noqa: E402

BAND_COLORS = ("#ff8c2e", "#57c7e3", "#a3d97e", "#e37ea9", "#d8b25c")
# Colours follow the system (Ubuntu/Yaru + libadwaita) theme: window,
# card and accent colours are the theme's own, in light and dark alike.
# Only the five band identities keep fixed colours — they are data.
CSS = """
.panel { background: @card_bg_color; border: 1px solid @borders; border-radius: 12px; }
.dim { opacity: 0.65; }
.mono { font-family: "DejaVu Sans Mono", monospace; font-size: 12px; }
.status-off { color: @warning_color; } .status-on { color: @success_color; }
button.accent { background: @accent_bg_color; color: @accent_fg_color; font-weight: bold; }
.sidebar row:selected { background: alpha(@window_fg_color, 0.10); }
.adi2-sidebar-column { background-color: @sidebar_bg_color; }
.adi2-sidebar-column headerbar { background: transparent; box-shadow: none; }
.bandhead { font-weight: bold; }
"""


def biquad_db(band: Band, freqs):
    """Magnitude response (dB) of one RBJ biquad at each frequency."""
    f0, gain, q = max(band.freq_hz, 1.0), band.gain_db, max(band.q, 0.05)
    if gain == 0.0 and band.type == "Peak":
        return [0.0] * len(freqs)
    A = 10 ** (gain / 40.0)
    w0 = 2 * math.pi * f0 / 48000.0
    alpha = math.sin(w0) / (2 * q)
    cw = math.cos(w0)
    if band.type == "Peak":
        b = (1 + alpha * A, -2 * cw, 1 - alpha * A)
        a = (1 + alpha / A, -2 * cw, 1 - alpha / A)
    elif band.type == "Shelf" and band.__dict__.get("_low", True):
        sq = 2 * math.sqrt(A) * alpha
        b = (A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw),
             A * ((A + 1) - (A - 1) * cw - sq))
        a = ((A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw),
             (A + 1) + (A - 1) * cw - sq)
    elif band.type == "Shelf":
        sq = 2 * math.sqrt(A) * alpha
        b = (A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw),
             A * ((A + 1) + (A - 1) * cw - sq))
        a = ((A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw),
             (A + 1) - (A - 1) * cw - sq)
    elif band.type == "High Pass":
        b = ((1 + cw) / 2, -(1 + cw), (1 + cw) / 2)
        a = (1 + alpha, -2 * cw, 1 - alpha)
    else:  # High Cut
        b = ((1 - cw) / 2, 1 - cw, (1 - cw) / 2)
        a = (1 + alpha, -2 * cw, 1 - alpha)
    out = []
    for f in freqs:
        w = 2 * math.pi * f / 48000.0
        c1, s1, c2, s2 = math.cos(w), -math.sin(w), math.cos(2 * w), -math.sin(2 * w)
        num = (b[0] + b[1] * c1 + b[2] * c2) ** 2 + (b[1] * s1 + b[2] * s2) ** 2
        den = (a[0] + a[1] * c1 + a[2] * c2) ** 2 + (a[1] * s1 + a[2] * s2) ** 2
        out.append(10 * math.log10(max(num, 1e-12) / max(den, 1e-12)))
    return out


def connection_action(ports_present: bool, connected: bool) -> str:
    """Device watcher decision, kept pure for testing."""
    if ports_present and not connected:
        return "connect"
    if not ports_present and connected:
        return "disconnect"
    return "none"


def band_response(band: Band, band_no: int, freqs):
    b = Band(band.type, band.gain_db, band.freq_hz, band.q)
    b.__dict__["_low"] = band_no == 1
    return biquad_db(b, freqs)


class EqCurve(Gtk.DrawingArea):
    """Log-frequency EQ graph; drag a band point to set freq/gain."""

    def __init__(self, get_bands, on_drag):
        super().__init__()
        self.set_content_width(360)   # minimum; the widget hexpands to fill
        self.set_hexpand(True)
        self.set_content_height(230)
        self.get_bands, self.on_drag = get_bands, on_drag
        self.set_draw_func(self._draw)
        drag = Gtk.GestureDrag()
        drag.connect("drag-begin", self._begin)
        drag.connect("drag-update", self._update)
        self.add_controller(drag)
        self._drag_band = None

    def _geom(self, w, h):
        return 46, 10, w - 56, h - 34  # x0, y0, plot w, plot h

    def _xy(self, freq, db, w, h):
        x0, y0, pw, ph = self._geom(w, h)
        x = x0 + pw * (math.log10(freq) - math.log10(20)) / (math.log10(20000) - math.log10(20))
        y = y0 + ph * (15 - db) / 30.0
        return x, y

    def _freq_db(self, x, y, w, h):
        x0, y0, pw, ph = self._geom(w, h)
        freq = 10 ** (math.log10(20) + (x - x0) / pw * (math.log10(20000) - math.log10(20)))
        db = 15 - (y - y0) / ph * 30.0
        return min(max(freq, 20), 20000), min(max(db, -12), 12)

    def _points(self, w, h):
        return [self._xy(b.freq_hz, b.gain_db, w, h) for b in self.get_bands()]

    def _begin(self, _g, x, y):
        w, h = self.get_width(), self.get_height()
        pts = self._points(w, h)
        self._drag_band = min(range(5), key=lambda i: (pts[i][0] - x) ** 2 + (pts[i][1] - y) ** 2)

    def _update(self, _g, dx, dy):
        if self._drag_band is None:
            return
        w, h = self.get_width(), self.get_height()
        pts = self._points(w, h)
        freq, db = self._freq_db(pts[self._drag_band][0] + dx, pts[self._drag_band][1] + dy, w, h)
        self.on_drag(self._drag_band, round(db * 2) / 2, freq)

    def _draw(self, _a, cr, w, h):
        x0, y0, pw, ph = self._geom(w, h)
        dark = Adw.StyleManager.get_default().get_dark()
        bg = (0.09, 0.10, 0.11) if dark else (0.97, 0.97, 0.98)
        ink = (1, 1, 1) if dark else (0, 0, 0)
        text = (0.62, 0.66, 0.70) if dark else (0.38, 0.40, 0.44)
        cr.set_source_rgb(*bg)
        cr.paint()
        cr.set_line_width(1)
        for db in (-12, -6, 0, 6, 12):
            _, y = self._xy(1000, db, w, h)
            cr.set_source_rgba(*ink, 0.14 if db else 0.30)
            cr.move_to(x0, y); cr.line_to(x0 + pw, y); cr.stroke()
            cr.set_source_rgb(*text)
            cr.move_to(4, y + 4); cr.show_text(f"{db:+d}" if db else " 0")
        for f in (20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000):
            x, _ = self._xy(f, 0, w, h)
            cr.set_source_rgba(*ink, 0.07)
            cr.move_to(x, y0); cr.line_to(x, y0 + ph); cr.stroke()
            cr.set_source_rgb(*text)
            label = f"{f // 1000}k" if f >= 1000 else str(f)
            cr.move_to(min(x - 6, w - 26), y0 + ph + 16); cr.show_text(label)
        freqs = [20 * (1000 ** (i / 119.0)) for i in range(120)]
        bands = self.get_bands()
        total = [0.0] * len(freqs)
        for n, band in enumerate(bands, 1):
            resp = band_response(band, n, freqs)
            total = [t + r for t, r in zip(total, resp)]
            cr.set_line_width(1.2)
            col = Gdk.RGBA(); col.parse(BAND_COLORS[n - 1])
            cr.set_source_rgba(col.red, col.green, col.blue, 0.45)
            for i, f in enumerate(freqs):
                x, y = self._xy(f, resp[i], w, h)
                cr.line_to(x, y) if i else cr.move_to(x, y)
            cr.stroke()
        cr.set_line_width(2.4)
        cr.set_source_rgb(1.0, 0.55, 0.18)
        for i, f in enumerate(freqs):
            x, y = self._xy(f, total[i], w, h)
            cr.line_to(x, y) if i else cr.move_to(x, y)
        cr.stroke()
        for i, (x, y) in enumerate(self._points(w, h)):
            col = Gdk.RGBA(); col.parse(BAND_COLORS[i])
            cr.set_source_rgb(col.red, col.green, col.blue)
            cr.arc(x, y, 7, 0, 2 * math.pi); cr.fill()
            cr.set_source_rgb(0.05, 0.05, 0.06)
            cr.move_to(x - 3, y + 4); cr.show_text(str(i + 1))


# Store builds (the snap) set ADI2_DEVICE_MEMORY=0: writing and naming the
# ADI-2's on-device preset slots and setups is not hardware-qualified, so
# those controls are left out, as in the Mac App Store release.
DEVICE_MEMORY = os.environ.get("ADI2_DEVICE_MEMORY", "1") != "0"


def bundled_profiles_dir():
    """The shipped EQ profiles: a source checkout's own, else the copy that
    install.sh, the .deb or the snap puts in <data dir>/rme-adi2-control."""
    candidates = [Path(__file__).parents[2] / "profiles"]
    if os.environ.get("SNAP"):
        candidates.append(Path(os.environ["SNAP"]) / "usr/share/rme-adi2-control/profiles")
    data_dirs = [os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")]
    data_dirs += (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    candidates += [Path(d) / "rme-adi2-control" / "profiles" for d in data_dirs if d]
    return next((c for c in candidates if c.is_dir()), None)


class Adi2Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="ADI-2 Control")
        self.set_default_size(1240, 800)
        self.device = "dac"
        self.transport: Transport | None = None
        self._syncing = False
        self._bt_panels = []
        self.state: dict = {}          # (address, index) -> raw (freq = Hz)
        self.bindings = []             # (address, Param, setter(real))
        self._loading = False
        self.eq_widgets = {}           # output key -> dict of band controls
        self.curves = {}
        self.advanced_expanders = []
        self._build_ui()
        self.refresh_ports()
        for key in proto.OUTPUTS:
            self._load_profile_into_page(key, EqProfile(output=key))
        style = Adw.StyleManager.get_default()
        style.connect("notify::dark",
                      lambda *_: [c.queue_draw() for c in self.curves.values()])
        GLib.idle_add(self._auto_connect)
        GLib.timeout_add_seconds(3, self._watch_device)

    def _auto_connect(self):
        """Connect and sync at launch when a DAC is already attached."""
        self.refresh_ports()
        if self._ports:
            self._connect_to_port(0)
        else:
            self._set_indicator("offline")
        return False

    def _watch_device(self):
        """Re-connect when the unit is switched on, notice when it goes.

        The ADI-2 has no remote power command in its MIDI protocol and
        its MIDI port vanishes when it is off, so watching for the port
        is the only — and sufficient — mechanism."""
        action = connection_action(bool(find_ports()), self.transport is not None)
        if action == "connect":
            self.refresh_ports()
            self._connect_to_port(0)
        elif action == "disconnect":
            self.transport = None
            self.device_label.set_text("No ADI-2 connected")
            self._set_indicator("offline")
        return True

    @staticmethod
    def _model_for_port(port_name: str) -> str:
        if "2/4" in port_name or "ADI-2/4" in port_name:
            return "pro24"
        if "Pro" in port_name:
            return "pro"
        return "dac"

    # ---------- state / sending ----------
    def raw_of(self, address, param: P.Param):
        if (address, param.index) in self.state:
            return self.state[(address, param.index)]
        return int(param.to_raw(param.default))

    def real_of(self, address, param: P.Param):
        if param.kind == "freq":
            return self.state.get((address, param.index), param.default)
        return param.to_real(self.raw_of(address, param))

    def set_param(self, address, param: P.Param, real, send=True):
        if self._loading and send:
            return
        if param.kind == "freq":
            self.state[(address, param.index)] = float(real)
            box = proto.encode_freq(address, param.index, float(real))
        elif address == proto.ADDR_DEVICE:
            self.state[(address, param.index)] = param.to_raw(real)
            box = proto.encode_device_param(param.index, param.to_raw(real))
        else:
            self.state[(address, param.index)] = param.to_raw(real)
            box = proto.encode_param(address, param.index, param.to_raw(real))
        if send and self.transport and not self._loading:
            try:
                self.transport.send(proto.params_message(self.transport.device_id, [box]))
            except Exception as exc:  # keep UI alive, surface the failure
                self.set_status(f"Send failed: {exc}", False)

    def send_containers(self, boxes):
        if self.transport and not self._loading:
            try:
                self.transport.send_params(boxes)
            except Exception as exc:
                self.set_status(f"Send failed: {exc}", False)

    def refresh_bindings(self, only=None):
        self._loading = True
        try:
            for address, param, setter in self.bindings:
                if only is None or address in only:
                    setter(self.real_of(address, param))
        finally:
            self._loading = False

    # ---------- chrome ----------
    def set_status(self, text, ok):
        self.status_label.set_text(text)
        self.status_label.set_tooltip_text(text)
        self.status_label.remove_css_class("status-on" if not ok else "status-off")
        self.status_label.add_css_class("status-on" if ok else "status-off")

    def _set_indicator(self, mode):
        """The persistent connection indicator in the content header:
        are the settings on screen live on the hardware, or not?"""
        modes = {
            "live": ("#2ec27e", "Connected · Live"),
            "syncing": ("#e8a13a", "Syncing…"),
            "offline": ("#e05252", "Not connected — changes are not on the device"),
            "detecting": ("#e8a13a", "Detecting…"),
        }
        color, text = modes[mode]
        self.status_label.set_markup(
            f'<span foreground="{color}">●</span>  {text}')
        self.status_label.set_tooltip_text(text)

    def _build_ui(self):
        display = Gdk.Display.get_default()
        data_dir = Path(__file__).parents[2] / "data"
        if display and data_dir.is_dir():
            Gtk.IconTheme.get_for_display(display).add_search_path(str(data_dir))
        Gtk.Window.set_default_icon_name("tech.norvi.Adi2Control")
        self.set_icon_name("tech.norvi.Adi2Control")
        provider = Gtk.CssProvider()
        if hasattr(provider, "load_from_string"):
            provider.load_from_string(CSS)
        else:
            provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        # Helios layout: TWO header bars, one per column, in a Paned.
        # The sidebar column reaches the window top as one unbroken
        # surface; the content header carries its own buttons instead
        # of a separate toolbar row wasting vertical space. Window
        # controls split to the outer edges: the sidebar header gives
        # up the end, the content header gives up the start.
        sidebar_header = Adw.HeaderBar()
        sidebar_header.set_show_end_title_buttons(False)
        app_title = Gtk.Label(label="ADI-2 Control")
        app_title.add_css_class("title-4")
        self.sidebar_title_label = app_title
        sidebar_header.set_title_widget(app_title)  # centred by the header bar

        content_header = Adw.HeaderBar()
        content_header.set_show_start_title_buttons(False)
        content_header.set_title_widget(Gtk.Box())
        self.header_box = content_header

        # Content-header controls. The app identity already sits in
        # the sidebar header, so the model is not repeated here; the
        # MIDI port (hw:…) lives in Settings where it means something.
        # device_label is kept unparented: connection code records the
        # detected model in it for Settings, it is not displayed.
        self.device_label = Gtk.Label(label="No ADI-2 connected", xalign=0)
        self.spinner = Gtk.Spinner()
        content_header.pack_start(self.spinner)
        self.sync_btn = Gtk.Button(label="Sync")
        self.sync_btn.set_tooltip_text("Sync from device")
        self.sync_btn.add_css_class("accent")
        self.sync_btn.connect("clicked", self._on_sync)
        content_header.pack_start(self.sync_btn)

        self.status_label = Gtk.Label(label="Detecting…")
        self.status_label.set_ellipsize(Pango.EllipsizeMode.END)
        self.status_label.set_max_width_chars(60)
        content_header.pack_end(self.status_label)
        settings_btn = Gtk.Button()
        settings_btn.set_icon_name("emblem-system-symbolic")
        settings_btn.set_tooltip_text("Settings — device model and MIDI port")
        settings_btn.connect("clicked", self._open_settings)
        self.settings_btn = settings_btn
        content_header.pack_end(settings_btn)

        self.sidebar = Gtk.ListBox()
        self.sidebar.add_css_class("sidebar")
        self.sidebar.add_css_class("navigation-sidebar")
        self.sidebar.set_vexpand(True)
        self.sidebar.connect("row-activated", self._on_nav)
        sidebar_column = Adw.ToolbarView()
        # The fill goes on the whole column (header + list), as in
        # Helios — painting only the list left the header bar above it
        # on window background, breaking the unbroken sidebar surface.
        sidebar_column.add_css_class("adi2-sidebar-column")
        sidebar_column.add_top_bar(sidebar_header)
        sidebar_column.set_content(self.sidebar)

        self.stack = Gtk.Stack(hexpand=True, vexpand=True)
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        content_toolbar = Adw.ToolbarView()
        content_toolbar.add_top_bar(content_header)
        content_toolbar.set_content(self.stack)

        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.set_start_child(sidebar_column)
        paned.set_end_child(content_toolbar)
        paned.set_position(218)
        paned.set_wide_handle(True)
        self.set_content(paned)

        self.pages = {}
        icons = {"line": "audio-speakers-symbolic",
                 "phones": "audio-headphones-symbolic",
                 "phones34": "audio-headphones-symbolic",
                 "input": "audio-input-microphone-symbolic",
                 "device": "audio-card-symbolic",
                 "presets": "bookmark-new-symbolic"}
        for key in ("line", "phones", "phones34"):
            self._add_page(key, proto.OUTPUTS[key]["label"],
                           self._build_output_page(key), icons[key])
        self._add_page("input", "Input (Pro)", self._build_simple_page(
            proto.ADDR_INPUT, P.INPUT_CHANNEL, "Input"), icons["input"])
        self._add_page("device", "Device", self._build_device_page(), icons["device"])
        self._add_page("presets", "Presets", self._build_presets_page(), icons["presets"])
        # Phones is the default page. select_row() alone only paints the
        # highlight — it does not fire row-activated, so without this the
        # stack kept showing Line Out until Phones was clicked again.
        self.stack.set_visible_child_name("phones")
        self.sidebar.select_row(self.sidebar.get_row_at_index(1))
        self._set_indicator("detecting")

    def _add_page(self, key, label, widget, icon_name=None):
        scroll = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
        scroll.set_child(widget)
        self.stack.add_named(scroll, key)
        self.pages[key] = widget
        row = Gtk.ListBoxRow()
        row.set_name(key)
        row_box = Gtk.Box(spacing=10, margin_start=12, margin_end=8,
                          margin_top=7, margin_bottom=7)
        if icon_name:
            row_box.append(Gtk.Image.new_from_icon_name(icon_name))
        row_box.append(Gtk.Label(label=label, xalign=0))
        row.set_child(row_box)
        self.sidebar.append(row)

    def _on_nav(self, _box, row):
        if row:
            self.stack.set_visible_child_name(row.get_name())

    def refresh_ports(self):
        self._ports = find_ports()

    def _connect_to_port(self, index: int):
        if not self._ports or index >= len(self._ports):
            self.set_status("No ADI-2 found — USB connected and MIDI Control = On?", False)
            return
        port = self._ports[index]
        self.device = self._model_for_port(port.name)
        self.transport = Transport(port.card_device, proto.DEVICE_IDS[self.device])
        model_label = {"dac": "ADI-2 DAC", "pro": "ADI-2 Pro",
                       "pro24": "ADI-2/4 Pro"}[self.device]
        self.device_label.set_text(model_label)  # port stays in Settings
        self._set_indicator("syncing")
        self._on_sync(None)

    def _open_settings(self, _btn):
        dialog = Adw.Dialog()
        dialog.set_title("Settings")
        dialog.set_content_width(430)
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                          margin_start=18, margin_end=18,
                          margin_top=14, margin_bottom=18)
        toolbar.set_content(content)
        dialog.set_child(toolbar)

        def row(label_text, widget):
            box = Gtk.Box(spacing=12)
            lab = Gtk.Label(label=label_text, xalign=0)
            lab.set_size_request(130, -1)
            box.append(lab)
            box.append(widget)
            content.append(box)

        model_dd = Gtk.DropDown.new_from_strings(
            ["ADI-2 DAC", "ADI-2 Pro", "ADI-2/4 Pro"])
        model_dd.set_selected(("dac", "pro", "pro24").index(self.device))

        def on_model(dd, _p):
            self.device = ("dac", "pro", "pro24")[dd.get_selected()]
            if self.transport:
                self.transport.device_id = proto.DEVICE_IDS[self.device]

        model_dd.connect("notify::selected", on_model)
        row("Device model", model_dd)

        self.refresh_ports()
        port_labels = [f"{p.card_device} — {p.name}" for p in self._ports] \
            or ["No ADI-2 found"]
        port_dd = Gtk.DropDown.new_from_strings(port_labels)
        if self._ports:
            port_dd.set_selected(0)

        def on_port(dd, _p):
            if self._ports:
                self._connect_to_port(dd.get_selected())

        port_dd.connect("notify::selected", on_port)
        row("MIDI port", port_dd)

        refresh_btn = Gtk.Button(label="Refresh ports")
        refresh_btn.connect("clicked", lambda _b: (self.refresh_ports(),
                                                   dialog.close(),
                                                   self._open_settings(None)))
        content.append(refresh_btn)
        note = Gtk.Label(xalign=0, wrap=True,
                         label="Model is normally detected from the port "
                               "name; change it only if detection is wrong. "
                               "Choosing a port connects and syncs at once.")
        note.add_css_class("dim")
        content.append(note)
        dialog.present(self)

    def _sync_ui(self, active: bool):
        if active:
            self.spinner.start()
        else:
            self.spinner.stop()
        self.sync_btn.set_sensitive(not active)

    def _on_sync(self, _btn):
        if not self.transport:
            self._set_indicator("offline")
            return
        if getattr(self, "_syncing", False):
            return
        self._syncing = True
        self._sync_ui(True)
        self._set_indicator("syncing")

        def work():
            try:
                state = self.transport.request_all()
                if not state:
                    GLib.idle_add(self._sync_failed,
                                  "no reply from device (check MIDI Control = On)")
                else:
                    GLib.idle_add(self._apply_synced, state)
            except Exception as exc:
                GLib.idle_add(self._sync_failed, str(exc))

        threading.Thread(target=work, daemon=True).start()

    def _sync_failed(self, message):
        self._syncing = False
        self._sync_ui(False)
        self.set_status(f"Sync failed: {message}", False)
        return False

    def _apply_synced(self, state):
        self._syncing = False
        self._sync_ui(False)
        self.state.update(state)
        self.refresh_bindings()
        for key, widgets in self.eq_widgets.items():
            self._refresh_eq_page(key)
        self._set_indicator("live")
        return False

    def _bt_section(self, left_addr):
        """Bass and Treble as their own titled sections, side by side,
        with preset behaviour underneath — not one mixed grid."""
        by_index = {p.index: p for p in P.EQ_EXTRA}
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                        margin_start=10, margin_end=10,
                        margin_top=8, margin_bottom=10)

        def titled(title_text, indices):
            panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5,
                            hexpand=True)
            panel.add_css_class("panel")
            head = Gtk.Label(label=title_text, xalign=0,
                             margin_start=10, margin_top=8)
            head.add_css_class("bandhead")
            panel.append(head)
            for idx in indices:
                panel.append(self._param_control(left_addr, by_index[idx],
                                                 compact=True))
            panel.append(Gtk.Box(margin_bottom=4))
            return panel

        pair = Gtk.Box(spacing=8, hexpand=True)
        bass = titled("Bass", (21, 22, 23))
        treble = titled("Treble", (24, 25, 26))
        pair.append(bass)
        pair.append(treble)
        outer.append(pair)
        self._bt_panels.append((bass, treble))

        behaviour = titled("Preset behaviour", (27,))
        outer.append(behaviour)
        return outer

    # ---------- generated parameter controls ----------
    def _param_control(self, address, param: P.Param, compact=False):
        box = Gtk.Box(spacing=8, margin_start=10 if compact else 0,
                      margin_end=10 if compact else 0)
        label = Gtk.Label(label=param.name, xalign=0)
        label.set_size_request(120 if compact else 190, -1)
        box.append(label)
        if param.kind in ("enum", "bool"):
            labels = list(param.labels) if param.kind == "enum" else ["Off", "On"]
            widget = Gtk.DropDown.new_from_strings(labels)
            widget.set_selected(min(max(self.raw_of(address, param), 0), len(labels) - 1))
            widget.connect("notify::selected", lambda d, _p, a=address, pr=param:
                           self.set_param(a, pr, float(d.get_selected())))

            def set_enum(real, w=widget, n=len(labels)):
                if 0 <= int(real) < n:  # ignore values outside this model's table
                    w.set_selected(int(real))

            self.bindings.append((address, param, set_enum))
            box.append(widget)
        else:
            adj = Gtk.Adjustment(value=self.real_of(address, param),
                                 lower=param.minimum, upper=param.maximum,
                                 step_increment=param.incr,
                                 page_increment=param.incr * 10)
            spin = Gtk.SpinButton(adjustment=adj, digits=2 if param.incr < 1 else 0)
            spin.set_size_request(110, -1)
            spin.connect("value-changed", lambda s, a=address, pr=param:
                         self.set_param(a, pr, s.get_value()))
            self.bindings.append((address, param,
                                  lambda real, w=spin, pr=param:
                                  w.set_value(min(max(real, pr.minimum), pr.maximum))))
            box.append(spin)
            if param.unit:
                unit_label = Gtk.Label(label=param.unit)
                unit_label.add_css_class("dim")
                box.append(unit_label)
        return box

    def _param_grid(self, address, params_list):
        grid = Gtk.Grid(column_spacing=18, row_spacing=6,
                        margin_start=12, margin_end=12, margin_top=10, margin_bottom=10)
        visible = P.for_device(params_list, self.device)
        for i, param in enumerate(visible):
            row, col = divmod(i, 2)
            grid.attach(self._param_control(address, param), col, row, 1, 1)
        return grid

    def _panel(self, title_text, child):
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                        margin_start=10, margin_end=10, margin_top=8, margin_bottom=4)
        frame.add_css_class("panel")
        head = Gtk.Label(label=title_text, xalign=0, margin_start=12, margin_top=8)
        head.add_css_class("bandhead")
        frame.append(head)
        frame.append(child)
        return frame

    def _collapsible(self, title_text, child):
        """Advanced section, collapsed until the user expands it."""
        expander = Gtk.Expander(label=title_text)
        expander.set_expanded(False)
        expander.set_hexpand(True)
        expander.set_margin_start(10)
        expander.set_margin_end(10)
        expander.set_margin_top(10)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        inner.add_css_class("panel")
        inner.append(child)
        expander.set_child(inner)
        self.advanced_expanders.append(expander)
        return expander

    def _build_simple_page(self, address, params_list, title_text):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        page.append(self._panel(title_text, self._param_grid(address, params_list)))
        return page

    def _build_device_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        page.append(self._panel("Device settings",
                                self._param_grid(proto.ADDR_DEVICE, P.DEVICE_PARAMS)))
        page.append(self._panel("Remapped keys (ADI-2 DAC)",
                                self._param_grid(proto.ADDR_DEVICE, P.REMAP_KEY_PARAMS)))
        note = Gtk.Label(xalign=0, margin_start=12, margin_top=6,
                         label="Sample Rate is display-only on the hardware. "
                               "Remap-key action lists follow the DAC table.")
        note.add_css_class("dim")
        page.append(note)
        return page

    # ---------- output pages: EQ hero + channel ----------
    def _build_output_page(self, key):
        out = proto.OUTPUTS[key]
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        widgets = {"bands": []}
        self.eq_widgets[key] = widgets

        curve = EqCurve(lambda k=key: self._bands_from_widgets(k),
                        lambda i, gain, freq, k=key: self._on_curve_drag(k, i, gain, freq))
        self.curves[key] = curve
        curve_box = Gtk.Box(margin_start=10, margin_end=10, margin_top=8,
                            hexpand=True)
        curve_box.add_css_class("panel")
        curve_box.append(curve)
        page.append(curve_box)

        band_row = Gtk.Box(spacing=8, margin_start=10, margin_end=10, margin_top=6)
        gain_i, freq_i, q_i = (4, 7, 10, 13, 17), (5, 8, 11, 14, 18), (6, 9, 12, 15, 19)
        for n in range(5):
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, hexpand=True)
            col.add_css_class("panel")
            dot = Gtk.Label(label="●")
            dot.set_markup(f'<span foreground="{BAND_COLORS[n]}">●</span> Band {n + 1}')
            dot.set_xalign(0); dot.set_margin_start(8); dot.set_margin_top(6)
            col.append(dot)
            controls = {}
            if n == 0 or n == 4:
                types = P.BAND_TYPES_1 if n == 0 else P.BAND_TYPES_5
                dd = Gtk.DropDown.new_from_strings(list(types))
                dd.set_selected(1 if types[1] == "Shelf" else 0)
                dd.set_margin_start(8)
                dd.set_margin_end(8)
                dd.set_margin_bottom(6)
                dd.connect("notify::selected", lambda _d, _p, k=key: self._send_eq(k))
                col.append(dd)
                controls["type"] = dd
            qmax = 5.0 if n >= 3 else 9.9
            for name, lo, hi, step, val in (("Gain dB", -12, 12, 0.5, 0.0),
                                            ("Freq Hz", 20, 20000, 1, 1000.0),
                                            ("Q", 0.5, qmax, 0.1, 1.0)):
                rowb = Gtk.Box(spacing=4, margin_start=8, margin_end=8,
                               margin_bottom=8)
                lab = Gtk.Label(label=name, xalign=0)
                lab.add_css_class("dim")
                rowb.append(lab)
                adj = Gtk.Adjustment(value=val, lower=lo, upper=hi,
                                     step_increment=step, page_increment=step * 10)
                spin = Gtk.SpinButton(adjustment=adj, digits=1 if step < 1 else 0)
                spin.set_hexpand(True)
                spin.connect("value-changed", lambda _s, k=key: self._send_eq(k))
                rowb.append(spin)
                col.append(rowb)
                controls[name.split()[0].lower()] = spin
            widgets["bands"].append(controls)
            col.set_size_request(196, -1)
            band_row.append(col)
        band_scroll = Gtk.ScrolledWindow(hexpand=True)
        band_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER)
        band_row.set_hexpand(True)
        band_scroll.set_child(band_row)
        page.append(band_scroll)

        actions = Gtk.Box(spacing=8, margin_start=10, margin_top=8)
        widgets["eq_enable"] = Gtk.Switch(active=True, valign=Gtk.Align.CENTER)
        widgets["eq_enable"].connect("notify::active", lambda _s, _p, k=key: self._send_eq(k))
        actions.append(Gtk.Label(label="EQ on"))
        actions.append(widgets["eq_enable"])
        widgets["bt_enable"] = Gtk.Switch(active=False, valign=Gtk.Align.CENTER)
        widgets["bt_enable"].connect("notify::active", lambda _s, _p, k=key: self._send_eq(k))
        actions.append(Gtk.Label(label="Bass/Treble on"))
        actions.append(widgets["bt_enable"])
        apply_btn = Gtk.Button(label="Apply EQ to device")
        apply_btn.add_css_class("accent")
        apply_btn.connect("clicked", lambda _b, k=key: self._send_eq(k, force=True))
        actions.append(apply_btn)
        export_btn = Gtk.Button(label="Export SysEx…")
        export_btn.connect("clicked", lambda _b, k=key: self._export_sysex(k))
        actions.append(export_btn)
        import_btn = Gtk.Button(label="Import EQ…")
        import_btn.connect("clicked", lambda _b, k=key: self._import_eq_dialog(k))
        actions.append(import_btn)
        page.append(actions)

        page.append(self._collapsible(
            "Advanced — Bass / Treble",
            self._bt_section(out["eq_left"])))
        channel_params = list(P.OUTPUT_CHANNEL)
        channel_params.insert(1, P.REF_LEVEL_PHONES if key != "line" else
                              (P.REF_LEVEL_LINE if self.device == "dac" else P.REF_LEVEL_LINE_PRO))
        page.append(self._collapsible(
            f"Advanced — {out['label']} channel",
            self._param_grid(out["channel"], channel_params)))
        return page

    def _bands_from_widgets(self, key):
        bands = []
        for n, controls in enumerate(self.eq_widgets[key]["bands"]):
            btype = "Peak"
            if "type" in controls:
                types = P.BAND_TYPES_1 if n == 0 else P.BAND_TYPES_5
                btype = types[controls["type"].get_selected()]
            bands.append(Band(btype, controls["gain"].get_value(),
                              controls["freq"].get_value(), controls["q"].get_value()))
        return bands

    def _profile_from_page(self, key):
        ch = proto.OUTPUTS[key]["channel"]
        return EqProfile(name=f"{proto.OUTPUTS[key]['label']} EQ", output=key,
                         bands=self._bands_from_widgets(key),
                         eq_enable=self.eq_widgets[key]["eq_enable"].get_active(),
                         bass_treble_enable=self.eq_widgets[key]["bt_enable"].get_active(),
                         loudness_enable=bool(self.state.get((ch, 20), 0)))

    def _load_profile_into_page(self, key, profile: EqProfile):
        widgets = self.eq_widgets[key]
        self._loading = True
        try:
            for n, (band, controls) in enumerate(zip(profile.bands, widgets["bands"])):
                if "type" in controls:
                    types = P.BAND_TYPES_1 if n == 0 else P.BAND_TYPES_5
                    controls["type"].set_selected(types.index(band.type))
                controls["gain"].set_value(band.gain_db)
                controls["freq"].set_value(band.freq_hz)
                controls["q"].set_value(band.q)
            widgets["eq_enable"].set_active(profile.eq_enable)
            widgets["bt_enable"].set_active(profile.bass_treble_enable)
        finally:
            self._loading = False
        self.curves[key].queue_draw()

    def _refresh_eq_page(self, key):
        out = proto.OUTPUTS[key]
        left = out["eq_left"]
        profile = self._profile_from_page(key)
        gain_i, freq_i, q_i = (4, 7, 10, 13, 17), (5, 8, 11, 14, 18), (6, 9, 12, 15, 19)
        for n, band in enumerate(profile.bands):
            if (left, gain_i[n]) in self.state:
                band.gain_db = self.state[(left, gain_i[n])] * 0.5
            if (left, freq_i[n]) in self.state:
                band.freq_hz = float(self.state[(left, freq_i[n])])
            if (left, q_i[n]) in self.state:
                band.q = self.state[(left, q_i[n])] * 0.1
        if (left, 3) in self.state:
            profile.bands[0].type = P.BAND_TYPES_1[self.state[(left, 3)]]
        if (left, 16) in self.state:
            profile.bands[4].type = P.BAND_TYPES_5[self.state[(left, 16)]]
        profile.eq_enable = bool(self.state.get((left, 2), 1))
        profile.bass_treble_enable = bool(self.state.get((left, 20), 0))
        self._load_profile_into_page(key, profile)

    def _on_curve_drag(self, key, band_no, gain, freq):
        controls = self.eq_widgets[key]["bands"][band_no]
        controls["gain"].set_value(gain)
        controls["freq"].set_value(freq)
        self._send_eq(key)

    def _send_eq(self, key, force=False):
        if self._loading and not force:
            return
        profile = self._profile_from_page(key)
        try:
            boxes = profile.containers()
        except ValueError as exc:
            self.set_status(str(exc), False)
            return
        for (a, i, v) in proto.parse_params(b"".join(boxes), P.freq_index_map()):
            self.state[(a, i)] = v
        self.curves[key].queue_draw()
        self.send_containers(boxes)
        if self.transport:
            self.set_status(f"EQ sent to {profile.output} ({len(boxes)} parameters)", True)

    def _export_sysex(self, key):
        profile = self._profile_from_page(key)
        dialog = Gtk.FileDialog()
        dialog.set_initial_name("adi2-eq.syx")

        def done(d, result):
            try:
                path = d.save_finish(result).get_path()
            except GLib.Error:
                return
            Path(path).write_bytes(profile.message(proto.DEVICE_IDS[self.device]))
            self.set_status(f"Wrote {path}", True)

        dialog.save(self, None, done)

    def _import_eq_dialog(self, output_key):
        """Import Equalizer APO / REW / AutoEq text, CSV, or JSON EQ."""
        from .importers import import_eq_file
        dialog = Gtk.FileDialog()
        dialog.set_title("Import EQ (APO/REW text, CSV, JSON)")

        def done(d, result):
            try:
                path = d.open_finish(result).get_path()
            except GLib.Error:
                return
            try:
                imported = import_eq_file(path, output=output_key)
            except Exception as exc:
                self.set_status(f"Import failed: {exc} — supported: Equalizer "
                                "APO/REW text, CSV, AutoEq JSON, ADI-2 JSON", False)
                return
            profile = imported.profile
            self._load_profile_into_page(output_key, profile)
            self.stack.set_visible_child_name(output_key)
            self._send_eq(output_key, force=True)
            note = f"Imported {profile.name} to {proto.OUTPUTS[output_key]['label']}"
            if imported.warnings:
                note += " — " + "; ".join(imported.warnings)
            self.set_status(note, True)

        dialog.open(self, None, done)

    # ---------- presets: local profiles + device slots ----------
    def _profile_dirs(self):
        user = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "rme-adi2" / "profiles"
        user.mkdir(parents=True, exist_ok=True)
        bundled = bundled_profiles_dir()
        return [bundled, user] if bundled else [user]

    def _list_profiles(self):
        found = []
        for folder in self._profile_dirs():
            if folder.is_dir():
                found += sorted(folder.glob("*.json"))
        return found

    def _build_presets_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        local = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6,
                        margin_start=12, margin_end=12, margin_top=8)
        self.profile_list = Gtk.ListBox()
        self.profile_list.add_css_class("boxed-list")
        local.append(self.profile_list)
        row = Gtk.Box(spacing=8)
        apply_local = Gtk.Button(label="Apply selected to current output page")
        apply_local.connect("clicked", self._apply_selected_profile)
        row.append(apply_local)
        self.new_profile_name = Gtk.Entry(placeholder_text="New profile name")
        row.append(self.new_profile_name)
        save_local = Gtk.Button(label="Save Phones EQ as profile")
        save_local.connect("clicked", self._save_local_profile)
        row.append(save_local)
        refresh = Gtk.Button(label="Refresh list")
        refresh.connect("clicked", lambda _b: self._refresh_profile_list())
        row.append(refresh)
        local.append(row)

        import_row = Gtk.Box(spacing=8)
        import_row.append(Gtk.Label(label="Import EQ file to"))
        self.import_target = Gtk.DropDown.new_from_strings(
            ["Line Out", "Phones 1/2", "Phones 3/4"])
        self.import_target.set_selected(1)  # Phones 1/2, the common case
        import_row.append(self.import_target)
        import_btn = Gtk.Button(label="Import EQ…")
        import_btn.add_css_class("accent")

        def _do_import(_b):
            key = ("line", "phones", "phones34")[self.import_target.get_selected()]
            self._import_eq_dialog(key)

        import_btn.connect("clicked", _do_import)
        self.presets_import_btn = import_btn
        import_row.append(import_btn)
        local.append(import_row)
        hint = Gtk.Label(xalign=0, wrap=True, label="Imports Equalizer APO / "
                         "REW / AutoEq filter text, CSV, and JSON EQ files, "
                         "applies them to the chosen output, and sends them "
                         "to the device when connected. Profiles are plain "
                         "JSON in ~/.config/rme-adi2/profiles.")
        hint.add_css_class("dim")
        local.append(hint)
        page.append(self._panel("Local EQ profiles", local))
        self._refresh_profile_list()
        if not DEVICE_MEMORY:
            return page

        dev = Gtk.Grid(column_spacing=10, row_spacing=8, margin_start=12,
                       margin_top=8, margin_bottom=10)
        dev.attach(Gtk.Label(label="EQ preset slot (1–20)", xalign=0), 0, 0, 1, 1)
        self.slot_spin = Gtk.SpinButton.new_with_range(1, 20, 1)
        dev.attach(self.slot_spin, 1, 0, 1, 1)
        self.preset_name = Gtk.Entry(placeholder_text="Preset name")
        dev.attach(self.preset_name, 2, 0, 1, 1)
        save_dev = Gtk.Button(label="Save Phones EQ to slot")
        save_dev.connect("clicked", self._save_device_preset)
        dev.attach(save_dev, 3, 0, 1, 1)
        load_dev = Gtk.Button(label="Load slot on Phones")
        load_dev.connect("clicked", self._load_device_preset)
        dev.attach(load_dev, 4, 0, 1, 1)
        dev.attach(Gtk.Label(label="Device setup (1–9)", xalign=0), 0, 1, 1, 1)
        self.setup_spin = Gtk.SpinButton.new_with_range(1, 9, 1)
        dev.attach(self.setup_spin, 1, 1, 1, 1)
        load_setup = Gtk.Button(label="Load setup")
        load_setup.connect("clicked", lambda _b: self._setup_command(load=True))
        dev.attach(load_setup, 3, 1, 1, 1)
        save_setup = Gtk.Button(label="Save setup")
        save_setup.connect("clicked", lambda _b: self._setup_command(load=False))
        dev.attach(save_setup, 4, 1, 1, 1)
        page.append(self._panel("Device memory (needs a connected ADI-2)", dev))
        return page

    def _refresh_profile_list(self):
        child = self.profile_list.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.profile_list.remove(child)
            child = nxt
        self._profile_paths = self._list_profiles()
        for path in self._profile_paths:
            try:
                name = json.loads(path.read_text()).get("name", path.stem)
            except Exception:
                name = path.stem
            row = Gtk.ListBoxRow()
            row.set_child(Gtk.Label(label=f"{name}  ({path.name})", xalign=0,
                                    margin_start=8, margin_top=5, margin_bottom=5))
            self.profile_list.append(row)

    def _apply_selected_profile(self, _btn):
        row = self.profile_list.get_selected_row()
        if not row:
            self.set_status("Select a profile first", False)
            return
        profile = EqProfile.load(self._profile_paths[row.get_index()])
        self._load_profile_into_page(profile.output, profile)
        self.stack.set_visible_child_name(profile.output)
        self._send_eq(profile.output, force=True)
        self.set_status(f"Applied {profile.name}", True)

    def _save_local_profile(self, _btn):
        name = self.new_profile_name.get_text().strip() or "Phones EQ"
        profile = self._profile_from_page("phones")
        profile.name = name
        slug = "".join(c if c.isalnum() else "-" for c in name.lower()).strip("-")
        path = self._profile_dirs()[1] / f"{slug or 'profile'}.json"
        profile.save(path)
        self._refresh_profile_list()
        self.set_status(f"Saved {path}", True)

    def _require_transport(self):
        if not self.transport:
            self.set_status("No device connected — device memory needs the ADI-2", False)
            return False
        return True

    def _save_device_preset(self, _btn):
        if not DEVICE_MEMORY:
            return
        if not self._require_transport():
            return
        slot = int(self.slot_spin.get_value())  # 1..20
        profile = self._profile_from_page("phones")
        boxes = []
        out = proto.OUTPUTS["phones"]
        # Preset data goes to addresses 13/14, committed by the flag word.
        for addr in (proto.ADDR_PRESET_L, proto.ADDR_PRESET_R):
            for band, (t_idx, g_idx, f_idx, q_idx) in zip(
                    profile.bands, ((3, 4, 5, 6), (None, 7, 8, 9), (None, 10, 11, 12),
                                    (None, 13, 14, 15), (16, 17, 18, 19))):
                if t_idx is not None:
                    types = P.BAND_TYPES_1 if t_idx == 3 else P.BAND_TYPES_5
                    boxes.append(proto.encode_param(addr, t_idx, types.index(band.type)))
                boxes.append(proto.encode_param(addr, g_idx, int(round(band.gain_db / 0.5))))
                boxes.append(proto.encode_freq(addr, f_idx, band.freq_hz))
                boxes.append(proto.encode_param(addr, q_idx, int(round(band.q / 0.1))))
        self.send_containers(boxes)
        flag = proto.encode_param(proto.ADDR_PRESET_L, 2, (slot - 1) << 4)
        self.send_containers([flag])
        name = self.preset_name.get_text().strip()
        if name:
            try:
                self.transport.send(proto.name_message(self.transport.device_id, slot, name))
            except Exception as exc:
                self.set_status(f"Preset saved, name failed: {exc}", False)
                return
        self.set_status(f"Saved EQ preset {slot} on device", True)

    def _load_device_preset(self, _btn):
        if not DEVICE_MEMORY:
            return
        if not self._require_transport():
            return
        slot = int(self.slot_spin.get_value())
        left = proto.OUTPUTS["phones"]["eq_left"]
        param = [p for p in P.EQ_EXTRA if p.index == 28][0]
        self.set_param(left, param, float(slot + 1))  # Manual=0, Temp=1, Preset N=N+1
        self.set_status(f"Loaded EQ preset {slot} on Phones", True)

    def _setup_command(self, load: bool):
        if not DEVICE_MEMORY:
            return
        if not self._require_transport():
            return
        n = int(self.setup_spin.get_value())
        sub = n if load else 0x09 + n
        try:
            self.transport.send(proto.preset_command_message(self.transport.device_id, sub))
            self.set_status(f"{'Loaded' if load else 'Saved'} device setup {n}", True)
        except Exception as exc:
            self.set_status(f"Setup command failed: {exc}", False)


def main(argv=None):
    app = Adw.Application(application_id="tech.norvi.Adi2Control")
    app.connect("activate", lambda a: Adi2Window(a).present())
    return app.run(argv)


if __name__ == "__main__":
    raise SystemExit(main())
