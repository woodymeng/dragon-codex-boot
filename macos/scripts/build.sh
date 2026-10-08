#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
target_arch="${1:-arm64}"
case "$target_arch" in arm64|x86_64) ;; *) echo 'Expected arm64 or x86_64' >&2; exit 2 ;; esac
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'macOS SDK required. Run on a Mac or use .github/workflows/macos.yml.' >&2
    exit 2
fi
xcrun --find swift
xcrun --show-sdk-path
output_root="${APP_OUTPUT_DIR:-$repo_root/build/macos-$target_arch}"
scratch_root="$repo_root/build/macos-spm-$target_arch"
app="$output_root/Dragon Codex Boot.app"
xcrun swift build --package-path "$repo_root/macos" --scratch-path "$scratch_root" -c release --arch "$target_arch"
binary_root="$(xcrun swift build --package-path "$repo_root/macos" --scratch-path "$scratch_root" -c release --arch "$target_arch" --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/media"
cp "$binary_root/DragonCodexBoot" "$app/Contents/MacOS/DragonCodexBoot"
chmod 755 "$app/Contents/MacOS/DragonCodexBoot"
cp "$repo_root/macos/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$repo_root/macos/Resources/launcher.example.json" "$app/Contents/Resources/"
cp "$repo_root/media/startup.mp4" "$repo_root/media/MEDIA_NOTICE.md" "$app/Contents/Resources/media/"
cp "$repo_root/LICENSE" "$repo_root/THIRD_PARTY_NOTICES.md" "$repo_root/macos/README.md" "$app/Contents/Resources/"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --identifier community.DragonCodexBoot "$app"
codesign --verify --deep --strict --verbose=2 "$app"
lipo "$app/Contents/MacOS/DragonCodexBoot" -verify_arch "$target_arch"
echo "Built $app (ad hoc signed; not notarized)"
