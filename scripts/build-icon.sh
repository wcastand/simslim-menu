#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

SOURCE="Assets/AppIcon.svg"
ICONSET="Assets/AppIcon.iconset"
OUTPUT="Assets/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() {
  local pixels="$1"
  local output="$2"
  magick -background none "$SOURCE" -resize "${pixels}x${pixels}" "$ICONSET/$output"
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"
echo "Built: $PWD/$OUTPUT"
