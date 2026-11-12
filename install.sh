#!/bin/sh
# Install ADI-2 Control for the current user (no root needed).
# On Ubuntu/Debian the .deb (see README, "Install") is the simpler route.
set -eu
cd "$(dirname "$0")"
pip install --user .
share=${XDG_DATA_HOME:-$HOME/.local/share}
mkdir -p "$share/applications" "$share/rme-adi2-control"
cp -R data/icons "$share/"
cp -R profiles "$share/rme-adi2-control/"
sed "s|^Exec=.*|Exec=$HOME/.local/bin/adi2-control|" \
    data/tech.norvi.Adi2Control.desktop \
    > "$share/applications/tech.norvi.Adi2Control.desktop"
gtk-update-icon-cache -q -t "$share/icons/hicolor" 2>/dev/null || true
echo "Installed. Run: adi2-control   (or launch 'ADI-2 Control')"
echo "Optional bit-perfect PipeWire setup: see README, 'Bit-perfect PipeWire'."
