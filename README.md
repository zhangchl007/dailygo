# DailyGo

<p align="center">
  <img src="assets/brand/dailygo-mark.svg" alt="DailyGo logo" width="96">
</p>

DailyGo is a native iOS and Android app for daily exercise and habit tracking at
Shenzhen University Normal College Affiliated High School (深大附中).

The open book in the logo represents learning and campus life. The orange flame
represents youth, action, and steady progress.

> **Project status:** active development. The native apps and core workflows are
> functional, but DailyGo is not yet ready for App Store or Play Store release.

## What Works Today

- Create, edit, archive, and restore habits
- Record daily completions and numeric progress
- View streaks and recent history
- Undo, restore, and correct completed entries
- Configure opt-in local reminders
- Persist data locally with Room on Android and SwiftData on iOS
- Import legacy data and create versioned local backups
- Share the same JSON acceptance fixtures across Swift and Kotlin domain tests
- Display English and Simplified Chinese UI on iOS

Accounts, cloud sync, production health-data integration, complete onboarding,
release signing, and store submission are still in progress.

## Tech Stack

| Area | Android | iOS |
| --- | --- | --- |
| UI | Kotlin + Jetpack Compose | Swift + SwiftUI |
| Storage | Room + bundled SQLite | SwiftData |
| Domain | Native Kotlin | Native Swift package |
| Minimum OS | Android 9 / API 28 | iOS 17 |

There is no cross-platform runtime or FFI layer. Each app is fully native, while
versioned fixtures in `tests/fixtures` keep domain behavior aligned.

## Requirements

### For domain and storage tests

- Git
- Java 17
- `make`
- macOS with Swift 6, or supported x86_64 Linux

The repository helpers download and verify the pinned Gradle distribution.
On supported Linux systems, the Swift helper can also download and verify Swift
6.0.3.

### For Android app development

- Java 17
- Android Studio with an Android SDK
- Android API 36
- Android Build Tools 35.0.0
- An API 35+ emulator or physical device for instrumentation tests

Set `ANDROID_HOME`, or create the ignored
`mobile/android/local.properties` file with your SDK path.

### For iOS app development

- macOS
- Xcode 16.4 or newer
- An iOS 17+ simulator or device

## Quick Start

Clone the repository and run the SDK-free validation:

```sh
git clone https://github.com/zhangchl007/dailygo.git
cd dailygo
make test
```

`make test` runs the Kotlin and Swift domain suites, Room storage tests, and
native project checks. It does not require an Android SDK.

### Run the Android app

Build a debug APK:

```sh
make native-android-build
```

The APK is written to:

```text
mobile/android/app/build/outputs/apk/debug/app-debug.apk
```

To work in Android Studio:

1. Add `androidApp=true` to your user Gradle properties file at
   `~/.gradle/gradle.properties`.
2. Open `mobile/android`.
3. Select the `app` run configuration and an API 35+ device.
4. Run the app.

The app module is opt-in so domain and storage tests can run without an Android
SDK.

### Run the iOS app

1. Open `mobile/ios/DailyGo.xcodeproj` in Xcode.
2. Select the shared `DailyGo` scheme.
3. Choose an iOS 17+ simulator.
4. Press **Run**.

To build and test from the command line:

```sh
make native-ios-test
```

Set `IOS_SIMULATOR_UDID` before running the command to select a specific installed
simulator.

## Common Commands

| Command | Purpose |
| --- | --- |
| `make test` | Run domain, storage, and project checks |
| `make native-test` | Run Kotlin, Swift, and Room tests |
| `make native-kotlin-test` | Run Kotlin domain tests |
| `make native-swift-test` | Run Swift domain tests |
| `make native-storage-test` | Run file-backed Room storage tests |
| `make native-project-check` | Validate native project structure |
| `make native-android-dependencies` | Verify Android dependency artifacts |
| `make native-android-build` | Build APKs and run Android unit tests and lint |
| `make native-android-ui-test` | Run Android instrumentation tests |
| `make native-ios-test` | Build and test the iOS app in a simulator |
| `make native-storage-durability` | Run macOS SwiftData durability checks |

You can also run the domain suites directly:

```sh
bash scripts/gradle.sh :domain:test
bash scripts/swift.sh test --package-path mobile/ios/Packages/DailyGoDomain
```

## Run on a Physical iPhone

1. In Xcode, sign in under **Xcode > Settings > Accounts**.
2. Connect and unlock the iPhone.
3. Enable **Developer Mode** under **Settings > Privacy & Security** on the phone.
4. Select your Apple development team in the DailyGo target's Signing settings.
5. Choose the connected iPhone and press **Run**.

For a command-line build, replace both placeholders:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPMENT_TEAM='<your Xcode team ID>'
export IOS_DEVICE_UDID='<your connected iPhone UDID>'

xcodebuild build \
  -project mobile/ios/DailyGo.xcodeproj \
  -scheme DailyGo \
  -configuration Debug \
  -destination "platform=iOS,id=$IOS_DEVICE_UDID" \
  -derivedDataPath .tools/ios-device-derived-data \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration

xcrun devicectl device install app \
  --device "$IOS_DEVICE_UDID" \
  .tools/ios-device-derived-data/Build/Products/Debug-iphoneos/DailyGo.app

xcrun devicectl device process launch \
  --device "$IOS_DEVICE_UDID" \
  com.dailygo
```

Keep personal signing details out of committed project files. If iOS reports an
untrusted developer profile, approve it under **Settings > General > VPN & Device
Management** on the phone. Personal Team profiles expire and may require a new
build and installation.

## Data and Security Notes

- HealthKit declarations do not grant access by themselves; production health
  queries and permission flows are not complete.
- Backups contain app records, pending changes, and retry receipts, but no raw
  biometric or location samples.
- Legacy imports require explicit timezone mapping and consent. Imported health
  provenance is treated as unverified.
- Corrupt or unsupported stores are reported instead of being destructively
  recreated.
- Build helpers use HTTPS and integrity verification; they do not pipe downloaded
  installers into a shell.

## Continuous Integration

GitHub Actions validates:

- Kotlin domain and Room durability tests on Ubuntu
- Swift domain tests on macOS
- Android APK, unit, lint, launch, and storage instrumentation tests
- iOS simulator app, unit, UI, and SwiftData durability tests

CI covers native startup, domain behavior, current persistence, legacy import,
backup and deletion behavior, and storage recovery. It does not certify release
signing, real health readings, physical-device performance, or store acceptance.

## Contributing

1. Create a focused branch.
2. Keep Android and iOS behavior aligned where the feature is shared.
3. Add or update shared fixtures for domain behavior changes.
4. Run the smallest relevant test command, then run `make test`.
5. Open a pull request with the behavior change and validation results.

Please do not commit SDK paths, signing teams, certificates, profiles, secrets,
generated build output, or files under `.tools/`.
