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
    atomic mutations/outbox receipts and 26 file-backed SQLite durability tests.

## P4 Persistence Progress

P4 currently implements habit creation, completed check-ins and separate numeric
partial-progress snapshots using
Room 2.7.2 and Google's prebuilt bundled SQLite driver 2.5.2. It adds no Cargo,
Rust FFI, JNA or application NDK build step. The completion API rejects below-target
values; `recordProgress` instead persists finite nonnegative values below the
target. Snapshots are not added together and never implicitly complete a goal.

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
invalid/archived rejection, separate progress, and immutable grace dates across
timezone changes. Both Room v1/v2 schemas are tracked; a real v1-to-v2 upgrade
preserves data, pending events and retry receipts. SQLite-full writes roll back
and can retry after space is restored. Corruption/unsupported versions surface
without destructive recreation; backup restoration is tested.

Room v2 and the initial SwiftData slice passed hosted CI at `ac9becc8`
(run 37436401130). Room v3 adds durable owner-deletion fences
with preserving v1/v2 upgrade paths. Twenty-six JVM SQLite tests pass, including
legacy import, versioned backups, atomic conflicts/deletion and disk-full import
rollback/recovery. The new Android transfer/deletion instrumentation test still
requires fresh native CI. Local WSL has no licensed Android SDK.
Startup UI remains unwired to persisted workflows, which belong to
the later product integration. Local outbox kinds are not a finalized server API.

SwiftData sources in `mobile/ios/Application/Storage` now include a v1-to-v2
upgrade, unique indexed scope models/inverse relationships for owner/habit reads,
direct result-key retry lookups, backups, legacy import and deletion fencing.
Eleven file-backed XCTest methods are wired into Xcode for upgrade, retries,
owner isolation, invalid imports, save rollback and unsupported/corrupt stores.
Production callers must share one writer actor; cross-repository/process
concurrency is not accepted by these tests.

Both adapters open legacy SQLite read-only and require explicit IANA timezone
mapping and consent to treat legacy health provenance as unverified. Imported
credits are labelled as legacy, not fabricated calendar/health evidence. Entity
IDs, UTC instants, credited dates and pending event IDs are retained; authoritative
outbox acknowledgements remain acknowledged even with stale legacy sync labels.
Unresolved/invalid sources are reported without target mutation or source changes.

Backups are platform-scoped version-1 JSON, bounded to 32 MiB, and preserve retry
receipts and pending changes without raw biometric/location samples. Historical
creation snapshots and credited timezones survive current habit timezone changes. Imports reject
ownership/version/identity/reference/value conflicts atomically; reimport never
resurrects an acknowledged event. Deletion clears owner data/events/receipts and
retains only a minimal anti-resurrection fence. A new local profile needs a new
owner ID; global account deletion and cross-platform sync remain P6.

Actual Swift record/backup/SQLite3 reader compilation and contract behaviors pass
on Linux using an integrity-verified cached header and existing SQLite runtime.
SwiftData framework sources/tests still require fresh macOS/iOS execution.
CI now also requires `bash scripts/native-storage-durability.sh` on macOS: a
temporary bounded disk image tests real disk-full rollback/retry, backup restore
and read-only legacy conversion, then is detached and removed. Its execution is
not yet claimed. Legacy user files/databases are untouched; P4 stays open until
all updated native gates pass.

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

Remaining P4 persistence/import, complete UI, actual health
queries, reminders, accounts/sync, device profiling, accessibility/localization,
beta, signing and store disclosures remain tracked tasks. Latest accepted native CI:
`ac9becc8b8b291aa99763a14b428fb97bd7e10f7`:
https://github.com/zhangchl007/dailygo/actions/runs/37436401130
Domain/Room tests, Android APK/unit/lint/emulator and Xcode simulator app/unit/UI
all passed. Retained artifacts include APKs/reports, Android startup PNG, Swift
domain results and iOS xcresult/logs. Launch tests check honest empty states and
recreation/relaunch. This pass covers Room v2 and the initial SwiftData slice,
not the new P4 upgrade/import/backup/deletion/recovery changes.
Local domain/storage, project checks and strict artifact checks pass; no local APK
or iOS simulator build is claimed and SDK licenses were not accepted in WSL.
Updated P4 native tests still require CI. Signing and real health/performance
validation need owner credentials and physical devices.
No cloud resources or store releases have been created.

# dailygo
