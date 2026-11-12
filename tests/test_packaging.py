"""Packaging invariants: the Linux icons are the macOS app icon, and the
version agrees across pyproject, the Debian changelog, the snap and AppStream."""
import re
import struct
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[1]
MAC = ROOT / "macOS" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
HICOLOR = ROOT / "data" / "icons" / "hicolor"
ICON = "tech.norvi.Adi2Control.png"

needs_mac = pytest.mark.skipif(not MAC.is_dir(), reason="macOS sources not in this tree")


def png_size(path):
    head = path.read_bytes()[:24]
    assert head[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", head[16:24])


def mac_icons_by_size():
    """Pixel width -> the set of macOS asset-catalog PNGs with that width."""
    found = {}
    for png in MAC.glob("*.png"):
        found.setdefault(png_size(png)[0], set()).add(png.read_bytes())
    return found


@needs_mac
def test_hicolor_icons_are_the_mac_icon():
    # Every size the Mac catalog has (16-512 px) is its exact bytes; only the
    # in-between Linux sizes (24, 48 px) are downscaled from the master.
    mac = mac_icons_by_size()
    shared = [icon for icon in HICOLOR.glob(f"*/apps/{ICON}") if png_size(icon)[0] in mac]
    assert len(shared) == 6
    for icon in shared:
        assert icon.read_bytes() in mac[png_size(icon)[0]], icon


@needs_mac
def test_source_tree_icon_is_the_mac_icon():
    assert (ROOT / "data" / ICON).read_bytes() in mac_icons_by_size()[512]


def test_hicolor_icons_match_their_directory_size():
    icons = sorted(HICOLOR.glob(f"*/apps/{ICON}"))
    assert len(icons) == 8
    for icon in icons:
        width, height = png_size(icon)
        assert f"{width}x{height}" == icon.parts[-3]


def test_versions_agree():
    version = re.search(r'^version = "([^"]+)"', (ROOT / "pyproject.toml").read_text(), re.M)[1]
    changelog = (ROOT / "debian" / "changelog").read_text().splitlines()[0]
    assert changelog.startswith(f"rme-adi2-control ({version})")
    assert f"version: '{version}'" in (ROOT / "snap" / "snapcraft.yaml").read_text()
    metainfo = (ROOT / "data" / "tech.norvi.Adi2Control.metainfo.xml").read_text()
    assert re.search(r'<release version="([^"]+)"', metainfo)[1] == version
