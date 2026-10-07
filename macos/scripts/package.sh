#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then echo 'Packaging .app requires macOS.' >&2; exit 2; fi
app="${APP_OUTPUT_DIR:-$repo_root/build/macos-arm64}/Dragon Codex Boot.app"
[[ -x "$app/Contents/MacOS/DragonCodexBoot" ]] || { echo 'Run macos/scripts/build.sh arm64 first.' >&2; exit 2; }
[[ "$(lipo -archs "$app/Contents/MacOS/DragonCodexBoot")" == arm64 ]] || { echo 'Package must be native arm64.' >&2; exit 2; }
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
mkdir -p "$repo_root/dist"
archive="$repo_root/dist/DragonCodexBoot-$version-macos-arm64-with-video.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd "$repo_root/dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
python3 "$script_root/verify-package.py" "$archive"
echo "$archive"
