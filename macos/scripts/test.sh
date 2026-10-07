#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
swift test --package-path "$repo_root/macos" --scratch-path "${SWIFT_TEST_SCRATCH:-$repo_root/build/macos-tests}" "$@"
