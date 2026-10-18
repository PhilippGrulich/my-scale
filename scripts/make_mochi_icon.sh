#!/bin/bash
# Renders the Mochi cat icons (light/dark/tinted app icon + Watch icon) from
# scripts/mochi-icon/icon.html via headless Chrome. Output is opaque 1024x1024.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
APP=App/Assets.xcassets/AppIcon.appiconset
WATCH=Watch/Assets.xcassets/AppIcon.appiconset
render() { # variant outfile
  local tmp; tmp="$(mktemp -d)"
  "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1024,1024 \
    --default-background-color=FFFFFFFF --screenshot="$tmp/raw.png" \
    "file://$PWD/scripts/mochi-icon/icon.html?v=$1" >/dev/null 2>&1
  # headless Chrome can pad the window height; crop to exactly 1024x1024
  sips -c 1024 1024 --cropOffset 0 0 "$tmp/raw.png" --out "$2" >/dev/null
  rm -rf "$tmp"
}
render light  "$APP/AppIcon-1024.png"
render dark   "$APP/AppIcon-Dark-1024.png"
render tinted "$APP/AppIcon-Tinted-1024.png"
render watch  "$WATCH/AppIcon-1024.png"
