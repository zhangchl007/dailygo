# Production Native Release Tasks

Unchecked tasks are release work remaining, not permission to label a prototype
production-ready. Mark completed only with recorded evidence.

## P1 Release Contract
- [x] T001 Establish spec, plan, task traceability and shared fixture schema. [REQ-001..015]
- [x] T002 Adopt native/local-first/privacy/SDD/TDD constitution. [REQ-010,012,014]

## P2 Native Domain
- [x] T003 Add pinned verified JVM build and Kotlin fixture tests before implementation. [REQ-001,003,005,006]
- [x] T004 Implement Kotlin schedules and deterministic streak/shield evaluation. [REQ-003,005,006]
- [x] T005 Add Swift package/tests and implement equivalent streak behavior. [REQ-003,005,006]
- [x] T006 Validate goals/titles and implement explicit calendar/grace policy in both languages. [REQ-002,004,007,008]
- [x] T007 Add honest partial/unknown health-evidence contracts and tests. [REQ-009,012]

## P3 Native Builds
- [ ] T008 Create Android app/manifest/resources/Gradle wrapper without FFI. [REQ-001]
- [ ] T009 Create Xcode project/scheme/capabilities/privacy configuration without FFI. [REQ-001,012]
- [ ] T010 Run native domain, Android build/tests, and macOS Xcode build/tests in CI. [REQ-014]

## P4 Persistence
- [ ] T011 Implement Room transactions, indexes, schema migration and restart tests. [REQ-008,010]
- [ ] T012 Implement actor-isolated SwiftData repository and recovery tests. [REQ-008,010]
- [ ] T013 Test legacy SQLite import preserving IDs/dates/pending changes. [REQ-010]
- [ ] T014 Implement safe export/import/deletion and data ownership boundaries. [REQ-010,012]

## P5 Product Workflows
- [ ] T015 Implement onboarding and full habit CRUD/goals/schedules. [REQ-002,013]
- [ ] T016 Implement goal progress/completion/correction and operation-error states. [REQ-008,013]
- [ ] T017 Implement streak/history/heat map with correct units and large-history queries. [REQ-005,006,013,015]
- [ ] T018 Implement reminder/settings/localization/accessibility/lifecycle flows. [REQ-013]
- [ ] T019 Replace fake HealthKit data with real windowed queries/permissions. [REQ-007,009,012]
- [ ] T020 Replace fake Health Connect data with real availability/permission/query flows. [REQ-007,009,012]
- [ ] T021 Verify permission denial, missing data and real device readings on both platforms. [REQ-009,014]

## P6 Accounts And Sync
- [ ] T022 Specify versioned auth/sync/conflict/tombstone API before server implementation. [REQ-011,012]
- [ ] T023 Implement authenticated ownership, safe account linking and account deletion. [REQ-011,012]
- [ ] T024 Implement transactional server dedupe/cursors/merge and client retry workers. [REQ-010,011]
- [ ] T025 Verify iOS/Android offline conflicts, partial retries, logout isolation and deletion. [REQ-011,012]

## P7 Release
- [ ] T026 Measure physical-device release performance/battery and address regressions. [REQ-015]
- [ ] T027 Complete security/accessibility/supported-OS quality gates. [REQ-012..015]
- [ ] T028 Complete signed TestFlight/Play beta, operational monitoring and restore drill. [REQ-014]
- [ ] T029 Complete store metadata/privacy declarations and staged rollout readiness. [REQ-012,014]
- [ ] T030 Retire Rust from app builds only after native parity/import validation. [REQ-001,010]

## Evidence

2026-10-06: fixture structure and Spec Kit prerequisites passed. Test-first Kotlin
and Swift runs failed before domain implementation, then passed after implementation.
Kotlin: 37 tests, zero failures (including 34 shared vectors). Swift: five XCTest
methods, zero failures, covering the same 34 vectors plus validation/provenance.
The conventional Gradle wrapper passed using the previously checksum-verified
distribution cache after this environment's Java download route timed out.

Native domain CI has been configured but has not run on GitHub. T010 remains open
until actual app build/UI targets exist and pass. The legacy app shells are not
yet wired to these libraries; no APK, iOS app or signed release is claimed.