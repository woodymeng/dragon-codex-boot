#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
if [[ "$(uname -s)" == Darwin ]] && ! printf 'import XCTest\n' | swiftc -typecheck - >/dev/null 2>&1; then
    if [[ $# -gt 0 ]]; then echo 'SwiftPM test arguments require XCTest / full Xcode.' >&2; exit 2; fi
    exec bash "$script_root/test-clt.sh"
fi
swift test --package-path "$repo_root/macos" --scratch-path "${SWIFT_TEST_SCRATCH:-$repo_root/build/macos-tests}" "$@"
