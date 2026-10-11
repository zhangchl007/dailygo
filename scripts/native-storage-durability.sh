#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    printf 'SwiftData durability requires macOS 14+ and Xcode.\n' >&2
    exit 1
fi
mkdir -p .tools
work=$(mktemp -d "$PWD/.tools/native-durability.XXXXXX")
mount="$work/mount"
cleanup() {
    if mount | grep -Fq " on $mount "; then
        hdiutil detach "$mount" -quiet || return
    fi
    rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$mount"
target="$(uname -m)-apple-macosx14.0"
xcrun swiftc -swift-version 6 -target "$target" -emit-library -emit-module -module-name DailyGoDomain \
    mobile/ios/Packages/DailyGoDomain/Sources/DailyGoDomain/*.swift \
    -emit-module-path "$work/DailyGoDomain.swiftmodule" -o "$work/libDailyGoDomain.dylib"
xcrun swiftc -swift-version 6 -target "$target" -I "$work" -L "$work" -lDailyGoDomain \
    -Xlinker -rpath -Xlinker "$work" mobile/ios/Application/Storage/*.swift \
    scripts/native-storage-durability.swift -o "$work/durability"
hdiutil create -quiet -size 32m -fs HFS+ -volname DailyGoDurability -type SPARSE "$work/volume.sparseimage"
hdiutil attach -quiet -nobrowse -mountpoint "$mount" "$work/volume.sparseimage"
"$work/durability" "$mount" "$PWD/tests/fixtures/legacy/v1.json"