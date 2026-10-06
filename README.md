# DailyGo

Production native fitness check-ins for iOS and Android. Implementation is in
progress; this repository does not yet contain release-ready mobile applications.

## Supported Direction

Swift/SwiftUI and Kotlin/Compose own platform code. Native domain libraries share
the same versioned JSON acceptance vectors. Rust and generated bindings are
preserved legacy code; do not use their fake health adapters in a public build.
The existing mobile UI shells have not yet been rewired to the native domain.

The active release contract and remaining work are in
[specs/006-production-native-release](specs/006-production-native-release).

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

## Release Gates Still Open

Real Android/Xcode app builds, native persistence/import, complete UI, actual health
queries, reminders, accounts/sync, device profiling, accessibility/localization,
beta, signing and store disclosures remain tracked tasks. Domain CI is not app
or store validation. iOS app, signing and HealthKit validation require macOS and
physical devices. No cloud resources or store releases have been created.# dailygo
