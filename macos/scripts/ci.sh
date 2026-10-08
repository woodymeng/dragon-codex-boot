#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then echo 'This verification entry requires a Mac and the macOS SDK.' >&2; exit 2; fi
mkdir -p "$repo_root/build/macos-ci-logs"
log_root="$repo_root/build/macos-ci-logs"
{
    sw_vers
    uname -m
    xcode-select -p
    xcrun --show-sdk-path
    xcrun swift --version
    if ! xcodebuild -version 2>/dev/null; then
        echo 'Full Xcode is not selected; using the selected Command Line Tools SDK.'
    fi
} | tee "$log_root/environment.log"
bash "$script_root/test.sh" 2>&1 | tee "$log_root/tests.log"
bash "$script_root/build.sh" arm64 2>&1 | tee "$log_root/build-arm64.log"
# Execute playback on the actual runner CPU. Cross-compilation is recorded separately.
host_arch="$(uname -m)"
if [[ "$host_arch" != arm64 ]]; then
    bash "$script_root/build.sh" "$host_arch" 2>&1 | tee "$log_root/build-host.log"
fi
host_binary="$repo_root/build/macos-$host_arch/Dragon Codex Boot.app/Contents/MacOS/DragonCodexBoot"
"$host_binary" --validate-config | tee "$log_root/config.json"
"$host_binary" --diagnose | tee "$log_root/diagnostics.json"
"$host_binary" --smoke-test | tee "$log_root/avfoundation-smoke.json"
bash "$script_root/package.sh" 2>&1 | tee "$log_root/package.log"
