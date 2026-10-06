# DailyGo

<img src="assets/brand/dailygo-mark.svg" alt="DailyGo 深大附中标志" width="96">

面向深大附中的每日运动与习惯成长应用。展开的书页代表校园与求知，向上的橙色火焰代表青春、行动与持续进步。

Production native fitness check-ins for iOS and Android. Implementation is in
progress; this repository does not yet contain release-ready mobile applications.

## Supported Direction

Swift/SwiftUI and Kotlin/Compose own platform code. Native domain libraries share
the same versioned JSON acceptance vectors. Rust and generated bindings are
preserved legacy code; do not use their fake health adapters in a public build.
New app targets use the native domain libraries and exclude legacy FFI source and
JNI binaries. The original mobile UI/health adapters remain preserved but are not
part of these app targets.

Release specifications under `specs/006-production-native-release` are local-only
and intentionally excluded from Git. Remaining public release gates are summarized
below.

## Native Domain Tests

```sh
make native-test
```

Or run independently:

```sh
bash scripts/gradle.sh :domain:test
bash scripts/swift.sh test --package-path mobile/ios/Packages/DailyGoDomain
```

The conventional Gradle wrapper is also available:

```sh
mobile/android/gradlew --no-daemon -p mobile/android :domain:test
```

Java 17 is required. The bootstrap obtains Gradle 8.13 from its official
distribution and verifies SHA-256 before execution. Dependencies are pinned,
locked, and covered by Gradle verification metadata. Java's wrapper download can
time out on restricted GitHub routes; the curl-based bootstrap is the alternative.

On macOS with Xcode's Swift installed, use `swift test --package-path
mobile/ios/Packages/DailyGoDomain`. On compatible x86_64 Linux, the helper downloads
Swift 6.0.3 from its official archive and verifies the upstream GPG signature
before extraction. Its historical signing key is now expired; the verified
archive signature was made while that release key was valid. Local Linux tooling
is not a choice of production Xcode or store SDK.

If a newer Ubuntu installation lacks the Ubuntu 24 runtime ABIs:

```sh
bash scripts/swift-runtime.sh
```

This uses a private signed Ubuntu package index and extracts SHA-256-verified
runtime libraries into ignored `.tools/`, without root or system installation.
Downloading executable tooling carries supply-chain risk; helpers require HTTPS,
official sources and integrity verification, and never pipe installers into a shell.

## Implemented In This Batch

- Explicit as-of dates; daily, weekday and ISO-week streaks.
- Deduplication, shield earning/caps and closed-period consumption.
- IANA timezone and DST-safe grace credits requiring overlapping workout context.
- Validated titles/targets, actual goal attainment and archived-habit rejection.
- Optional, source-attributed health evidence; manual data never becomes health-backed.
- Kotlin and Swift tests consuming 34 shared acceptance vectors.
- Android app module, launcher manifest, native Compose entry, resources and startup tests.
- Xcode app/unit/UI targets, shared scheme, SwiftUI entry, local domain package,
  read-only HealthKit declaration, purpose string and privacy manifest.
- Native CI jobs for APK/unit/lint/emulator checks and Xcode simulator tests.
- P4 Room storage foundation with owner-scoped keys, immutable date credits,
  atomic mutations/outbox receipts and ten file-backed SQLite durability tests.

## P4 Persistence Progress

The first P4 slice implements habit creation and completed check-in storage using
Room 2.7.2 and Google's prebuilt bundled SQLite driver 2.5.2. It adds no Cargo,
Rust FFI, JNA or application NDK build step. Numeric partial progress is rejected
by this completion API; partial-progress storage is not implemented yet.

Run the focused suite without an Android SDK:

```sh
make native-storage-test
```

The same persistence sources in `mobile/android/storage/src/shared/kotlin` are
compiled by the JVM test module and independently by the Android app. Only the
database builders differ. This is Android persistence testing, not a Kotlin
runtime shared with iOS; iOS remains native Swift/SwiftData.

File-backed tests cover habit/check-in outbox failure rollback, reopen, durable
retries after acknowledgement, concurrent same-day completions, owner isolation,
invalid/partial/archived rejection, and immutable grace dates. The exported Room
v1 schema is tracked. Unknown schema versions fail without destructive migration;
actual upgrade migrations still need implementation/evidence when the schema evolves.

The Android builder and an instrumentation reopen test are added but not compiled
or run here. Startup UI remains unwired to persisted workflows, which belong to
the later product integration. Local outbox kinds are not a finalized server API.
SwiftData, legacy SQLite import, safe export/import/deletion and native device
recovery evidence remain open P4 work. Legacy files/databases are untouched.

## Native App Builds

SDK-free checks remain independent of mobile SDK installation:

```sh
make native-test native-project-check native-android-dependencies
```

Android requires Java 17 and a licensed Linux Android SDK when running in WSL:
API 36 platform, Build Tools 35.0.0, platform tools, and an emulator/device for
instrumentation. Configure `ANDROID_HOME` or the ignored Android `local.properties`.
Do not point WSL builds at Windows SDK executables. License acceptance is an owner
action; the scripts do not accept licenses for you.

```sh
make native-android-build
make native-android-ui-test
```

Debug APK output: `mobile/android/app/build/outputs/apk/debug/app-debug.apk`.
The app is opt-in (`-PandroidApp=true`) so domain tests stay SDK-free.
App/runtime locks and verification hashes are recorded; any additional build-tool
artifacts found by the first SDK build must be reviewed and added to verification
metadata, not bypassed with lenient/off verification.

On macOS, open `mobile/ios/DailyGo.xcodeproj` and use the shared `DailyGo` scheme.
CI selects Xcode 16.4. Run unsigned simulator app/unit/UI tests with:

```sh
make native-ios-test
```

The script selects an available iPhone simulator matching Xcode's simulator SDK.
`IOS_SIMULATOR_UDID` can select
a specific installed device. Real-device builds require your Apple team and
provisioning; `com.dailygo` remains a provisional bundle/application identifier.

P3 currently supplies startup entries, not persisted habit workflows. The empty
state contains no fabricated habits or health readings. Health queries and their
permission workflows remain P5; declarations alone do not grant health access.

## Release Gates Still Open

Successful Android/Xcode app builds, remaining P4 persistence/import, complete UI, actual health
queries, reminders, accounts/sync, device profiling, accessibility/localization,
beta, signing and store disclosures remain tracked tasks. The first native CI run
for revision `af93b37` passed Kotlin/Room, Swift domain and legacy Rust tests but
failed Android AAPT2 dependency verification and macOS project validation.
Those blockers have local fixes; a new remote run must confirm them before T010
can close. Launch tests now check empty-state visibility, recreation/relaunch and
retain screenshots. Local domain tests, Gradle configuration/artifact resolution,
Swift startup typechecking and Xcode project-structure checks pass; no local APK or
iOS simulator build is claimed. SDK licenses were not accepted in this WSL environment.
First SDK builds may expose further compile/tool verification issues. iOS app,
signing and HealthKit validation require macOS and physical devices.
No cloud resources or store releases have been created.

# dailygo
