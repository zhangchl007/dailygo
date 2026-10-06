# Native Release Implementation Plan

## Architecture

Use independently tested Swift and Kotlin domain libraries, shared JSON acceptance
vectors, SwiftUI/SwiftData and Compose/Room adapters, and real platform health APIs.
Domain libraries must not depend on UI, persistence, network, or sensors. As-of
dates and instants are supplied by callers; there is no hidden system clock.

Android starts with a standalone JVM domain build runnable without an Android SDK.
iOS starts with a local Swift package runnable with `swift test`; macOS/Xcode is
required for app/UI/signing validation. Native app projects follow the proven
domain contract. Existing shells stay clearly legacy until rewired and tested.

Optional sync requires a versioned HTTPS contract and server ownership. Recommended
server: one Kotlin/Ktor service with PostgreSQL, not an unnecessary microservice
fleet. No provider or cloud lifecycle operation is implied by this plan.

## Phases And Requirement Mapping

| Phase | Requirements | Evidence |
|---|---|---|
| P1 Release contract/fixtures | 001-015 | spec.md, tasks.md, shared fixtures |
| P2 Native domain parity | 002-009 | Kotlin/Swift unit and fixture tests |
| P3 Native application builds | 001,013,014 | Gradle APK, Xcode simulator build |
| P4 Durable storage/import | 008,010,012 | rollback/reopen/migration/import tests |
| P5 Complete UI and real health | 002,007-009,013 | UI and physical-device evidence |
| P6 Optional accounts/sync | 010-012 | API and two-device integration tests |
| P7 Profiling/beta/store release | 012-015 | device measurements, signed builds |

Pinned official downloads must be checksum/signature verified before execution.
Use lockfiles and dependency verification. Preserve Rust and legacy databases.
Do not describe scaffold completion, Rust tests, or a simulator build as a release.

## Current Validation

Shared fixture structure is validated before domain implementation. Then add
native tests first, observe failure, implement the smallest behavior, and rerun.
Track executable evidence and actual limitations in tasks.md. Coverage percentage
is a nonblocking review signal, not a substitute for behavioral tests.