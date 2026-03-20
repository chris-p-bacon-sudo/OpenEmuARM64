#!/bin/bash
# NOTE: This script was created during the original ARM64 port and contained
# hardcoded paths from the original developer's machine. Set ICON_SOURCE to
# your source PNG (1024x1024 recommended) before running.

ICON_SOURCE="${ICON_SOURCE:-}"
ICONSET_PATH="${ICONSET_PATH:-$(dirname "$0")/OpenEmu/Graphics.xcassets/OpenEmu.appiconset}"

if [ -z "$ICON_SOURCE" ]; then
    echo "Error: Set ICON_SOURCE to your icon PNG path before running."
    exit 1
fi

echo "Generating icons from $ICON_SOURCE..."

# Function to resize and copy
generate_icon() {
    local size=$1
    local name=$2
    sips -z $size $size "$ICON_SOURCE" --out "$ICONSET_PATH/$name-srgb.png" > /dev/null
    sips -z $size $size "$ICON_SOURCE" --out "$ICONSET_PATH/$name-p3.png" > /dev/null
}

generate_icon 16 "icon-16"
generate_icon 32 "icon-32"
generate_icon 64 "icon-64"
generate_icon 128 "icon-128"
generate_icon 256 "icon-256"
generate_icon 512 "icon-512"
generate_icon 1024 "icon-1024"

echo "Icons generated successfully in $ICONSET_PATH"
