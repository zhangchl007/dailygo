# DailyGo Production Native Release

Status: implementation in progress. This replaces the Rust/UniFFI mobile architecture,
not the requirement for a production-quality release. Existing Rust databases and
source remain intact until import and parity checks pass.

## Product Requirements

- REQ-001: Installable Swift/SwiftUI iOS 17+ and Kotlin/Compose Android 9+ apps
  must build without Rust, UniFFI, JNA, or the Android NDK.
- REQ-002: Users can create, edit, archive, and delete habits with a trimmed
  1..100-character title, a supported schedule, and a valid metric. Numeric
  targets must be finite and strictly positive. Archived habits reject new entries.
- REQ-003: Schedules support daily, weekdays, and an ISO-week target of 1..7
  distinct completed dates. All calculations take an explicit as-of date.
- REQ-004: Check-ins use a UTC instant, a valid IANA schedule timezone, an immutable
  credited date, and a credit reason. Invalid/future dates are rejected, not ignored.
  Timezone changes do not reclassify stored historical dates.
- REQ-005: Streaks count completed required days, or completed weeks for weekly
  targets. Nonrequired weekdays do not break or extend a weekday streak. Current
  open periods do not break a streak until they close. Duplicate dates count once.
- REQ-006: Every seven consecutive unshielded completed required periods earns one
  shield, capped at three. A closed missed required period consumes one available
  shield without incrementing the streak; multiple misses consume separately.
  Shielded periods reset earning progress. An unprotected miss resets the streak.
  Calculation is deterministic and does not mutate storage. Weekly rewards and
  shields operate on weeks, and UI labels must state the streak unit.
- REQ-007: Default grace cutoff is 03:00 in the schedule timezone. Previous-day
  credit requires an actual workout starting on that day and continuing past
  midnight, before cutoff, and no completion already credited to that day.
  Plain manual entries do not silently claim a previous date. DST uses local
  calendar arithmetic, not a fixed 24-hour duration.
- REQ-008: Numeric completion requires a finite nonnegative value reaching the
  goal. Completion goals need no numeric value. One completion per habit/credited
  date is idempotent; partial progress is distinct from completing a goal.
- REQ-009: HealthKit/Health Connect evidence must be real, windowed, deduplicated,
  and attributed. Missing/denied evidence is unknown, not zero or suspicious.
  Manual input never receives a health-data-backed label. This is not tamper-proof
  anti-cheat and must not rely on fabricated fitness profiles or arbitrary HR scores.
- REQ-010: Local mutations and outbox events commit atomically, survive restart,
  and support tested schema upgrades, legacy import, export, and deletion.
- REQ-011: Full offline usage needs no account. Optional accounts synchronize iOS
  and Android with authenticated ownership, event idempotency, durable cursors,
  deterministic conflicts, tombstones, retry, and safe guest-data attachment.
- REQ-012: Raw biometric samples and location histories remain off the sync API
  by default. Consent, retention, secure credentials, export, and account deletion
  must be explicit. Logs must not contain health data or authentication secrets.
- REQ-013: Onboarding, today/detail/edit, history/heat map, reminders, settings,
  and sync states include accessible empty/loading/error/retry/permission flows,
  English and Simplified Chinese, dynamic type, and process-recreation recovery.
- REQ-014: Native build/unit/UI gates run in CI; physical-device health testing,
  profiling, signing, beta, privacy disclosures, and store readiness gate release.
- REQ-015: Proposed measured release budgets: p95 cold local launch <=2 seconds,
  p95 durable offline completion <=150 ms, and <1% janky frames in a defined
  10,000-record history benchmark. These are goals, not existing results.

## Acceptance Scenarios

The versioned vectors in `tests/fixtures/streaks.json` are shared by Swift and
Kotlin. They cover empty/daily history, deduplication, weekdays, weekly targets,
shield earning/caps/closed-period consumption/multiple misses, and invalid input.
Each implementation must consume the same file, not duplicate expected results.

Additional suites must exercise title/target bounds, archived writes, goal
attainment, midnight/DST/travel/grace, unknown health evidence, atomic rollback,
restart/upgrades/import, permissions, and actual multi-device synchronization.

## Release Decisions Still Requiring Ownership

Launch date/team capacity, Mac and physical-device access, developer accounts,
bundle identifiers, markets/data residency, authentication provider, backend
hosting, and existing deployed data are not confirmed. No infrastructure is
provisioned and no signed/public release is authorized by this document.
GPS/social/payments/watches/widgets are not committed launch requirements.