#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v xcodebuild >/dev/null || { printf 'iOS app tests require macOS with Xcode.\n' >&2; exit 1; }
command -v xcrun >/dev/null || { printf 'Xcode command-line tools are missing.\n' >&2; exit 1; }

simulator=${IOS_SIMULATOR_UDID:-}
if [[ -z "$simulator" ]]; then
    simulator=$(xcrun simctl list devices available --json | swift -e '
        import Foundation
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let document = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let devices = document["devices"] as! [String: [[String: Any]]]
        let runtimes = devices.keys.filter { $0.contains("SimRuntime.iOS-") }.sorted().reversed()
        let phones = runtimes.flatMap { devices[$0]! }.filter {
            ($0["isAvailable"] as? Bool == true) && ($0["name"] as? String)?.hasPrefix("iPhone") == true
        }
        guard let selected = phones.first, let identifier = selected["udid"] as? String else {
            FileHandle.standardError.write(Data("No available iPhone simulator.\n".utf8))
            exit(1)
        }
        print(identifier)
    ')
fi

xcodebuild test \
    -project "$root/mobile/ios/DailyGo.xcodeproj" \
    -scheme DailyGo \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$root/.tools/ios-derived-data" \
    CODE_SIGNING_ALLOWED=NO