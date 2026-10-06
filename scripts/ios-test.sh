#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v xcodebuild >/dev/null || { printf 'iOS app tests require macOS with Xcode.\n' >&2; exit 1; }
command -v xcrun >/dev/null || { printf 'Xcode command-line tools are missing.\n' >&2; exit 1; }

simulator=${IOS_SIMULATOR_UDID:-}
if [[ -z "$simulator" ]]; then
    sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
    simulator=$(xcrun simctl list devices available --json | swift "$root/scripts/select-ios-simulator.swift" "$sdk")
fi
printf 'Testing iOS Simulator UDID: %s\n' "$simulator"

xcodebuild test \
    -project "$root/mobile/ios/DailyGo.xcodeproj" \
    -scheme DailyGo \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$root/.tools/ios-derived-data" \
    CODE_SIGNING_ALLOWED=NO