"""GUI regressions: theme-synced colours, auto-connect, band padding,
sidebar icons. Needs a display — skipped (not failed) without one."""
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[1] / "src"))
if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
    pytest.skip("no display", allow_module_level=True)
gi = pytest.importorskip("gi")
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gtk, Pango  # noqa: E402

if not Gtk.init_check() or Gdk.Display.get_default() is None:
    pytest.skip("no display", allow_module_level=True)

from adi2.app import CSS, Adi2Window, connection_action  # noqa: E402


@pytest.fixture(scope="module")
def window():
    app = Adw.Application(application_id="tech.norvi.Adi2TestGui")
    win_holder = {}

    def activate(a):
        win_holder["win"] = Adi2Window(a)

    app.connect("activate", activate)
    app.register()
    app.activate()
    yield win_holder["win"]


def test_no_hardcoded_window_colors():
    assert "#17191c" not in CSS and "@accent_bg_color" in CSS
    assert "@card_bg_color" in CSS


def test_sidebar_rows_have_icons(window):
    row = window.sidebar.get_row_at_index(0)
    box = row.get_child()
    kinds = []
    child = box.get_first_child()
    while child:
        kinds.append(child)
        child = child.get_next_sibling()
    assert any(isinstance(c, Gtk.Image) for c in kinds)
    assert any(isinstance(c, Gtk.Label) for c in kinds)


def test_band_q_row_has_bottom_padding(window):
    bands = window.eq_widgets["phones"]["bands"]
    q_spin = bands[0]["q"]
    assert q_spin.get_parent().get_margin_bottom() >= 8


def test_auto_connect_hook_present(window):
    assert callable(window._auto_connect)


def test_connection_action_decisions():
    assert connection_action(True, False) == "connect"
    assert connection_action(False, True) == "disconnect"
    assert connection_action(True, True) == "none"
    assert connection_action(False, False) == "none"


def test_advanced_sections_collapsed_by_default(window):
    assert window.advanced_expanders, "no collapsible advanced sections"
    assert all(not e.get_expanded() for e in window.advanced_expanders)


def test_curve_expands_horizontally(window):
    assert window.curves["phones"].get_hexpand()


def _walk(widget):
    yield widget
    child = widget.get_first_child() if hasattr(widget, "get_first_child") else None
    while child:
        yield from _walk(child)
        child = child.get_next_sibling()


def test_header_has_no_model_or_port_dropdowns(window):
    dropdowns = [w for w in _walk(window.header_box)
                 if isinstance(w, Gtk.DropDown)]
    assert dropdowns == []
    assert callable(window._open_settings)


def test_launch_shows_highlighted_phones_page(window):
    # Regression: the sidebar highlighted Phones while the stack still
    # showed Line Out until Phones was clicked a second time.
    assert window.stack.get_visible_child_name() == "phones"
    row = window.sidebar.get_selected_row()
    assert row is not None and row.get_name() == "phones"


def test_device_label_hides_raw_port(window):
    assert "hw:" not in window.device_label.get_text()


def test_single_identity_no_icon_in_sidebar_title(window):
    # One identity only: the sidebar title, centred, with no icon, and
    # the model label is not displayed in the content header.
    assert window.sidebar_title_label.get_text() == "ADI-2 Control"
    assert window.sidebar_title_label.get_parent() is not None
    assert window.device_label.get_parent() is None


def test_indicator_modes(window):
    for mode, needle in (("live", "Connected · Live"),
                         ("offline", "Not connected"),
                         ("syncing", "Syncing")):
        window._set_indicator(mode)
        assert needle in window.status_label.get_text()


def test_presets_page_has_import_button(window):
    assert window.presets_import_btn.get_label() == "Import EQ…"
    targets = window.import_target.get_model()
    labels = [targets.get_string(i) for i in range(targets.get_n_items())]
    assert labels == ["Line Out", "Phones 1/2", "Phones 3/4"]


def test_bass_and_treble_are_separate_sections(window):
    assert window._bt_panels, "no bass/treble sections built"
    bass, treble = window._bt_panels[1]  # phones page
    bass_text = [w.get_text() for w in _walk(bass) if isinstance(w, Gtk.Label)]
    treble_text = [w.get_text() for w in _walk(treble) if isinstance(w, Gtk.Label)]
    assert any("Bass Gain" in t for t in bass_text)
    assert not any("Treble" in t for t in bass_text if "Bass" not in t)
    assert any("Treble Gain" in t for t in treble_text)


def test_status_label_ellipsizes_with_tooltip(window):
    assert window.status_label.get_ellipsize() == Pango.EllipsizeMode.END
    long_msg = "Imported profile — " + "; ".join(f"warning {i}" for i in range(10))
    window.set_status(long_msg, True)
    assert window.status_label.get_tooltip_text() == long_msg


def _labels(widget):
    found, child = [], widget.get_first_child()
    while child is not None:
        if isinstance(child, Gtk.Label):
            found.append(child.get_label())
        found += _labels(child)
        child = child.get_next_sibling()
    return found


def test_store_build_leaves_out_device_memory(window, monkeypatch):
    import adi2.app as app
    assert any("Device memory" in t for t in _labels(window._build_presets_page()))
    monkeypatch.setattr(app, "DEVICE_MEMORY", False)
    labels = _labels(window._build_presets_page())
    assert "Local EQ profiles" in labels
    assert not any("Device memory" in t for t in labels)
