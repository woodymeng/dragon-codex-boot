#!/bin/bash
set -euo pipefail
script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_root/../.." && pwd)"
output="$repo_root/build/clt-tests"
mkdir -p "$output"
echo 'XCTest unavailable: running the same core test methods with the CLT assertion runner.'
swiftc -emit-library -emit-module -enable-testing -module-name LauncherCore \
    "$repo_root"/macos/Sources/LauncherCore/*.swift \
    -emit-module-path "$output/LauncherCore.swiftmodule" -o "$output/libLauncherCore.dylib"
python3 "$script_root/generate-clt-runner.py" \
    "$repo_root/macos/Tests/LauncherCoreTests/CoreTests.swift" "$output/main.swift"
swiftc -D DRAGON_CLT_TESTS -I "$output" -L "$output" -lLauncherCore \
    -Xlinker -rpath -Xlinker "$output" \
    "$repo_root/macos/TestSupport/CLTAssertions.swift" \
    "$repo_root/macos/Tests/LauncherCoreTests/CoreTests.swift" "$output/main.swift" \
    -o "$output/CoreTests"
"$output/CoreTests"
