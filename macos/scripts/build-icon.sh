#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output="${1:?Specify the output Resources directory}"
iconset="$repo_root/build/DragonCodexBoot.iconset"
mkdir -p "$iconset" "$output"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$repo_root/macos/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$repo_root/macos/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$output/AppIcon.icns"
