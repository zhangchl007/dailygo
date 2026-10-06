# DailyGo Constitution

## Core Principles

### I. Native Production Architecture
Swift/SwiftUI and Kotlin/Compose own platform implementations. Shared specs and
acceptance vectors prevent drift. Domain code has no UI/database/sensor/network
dependency. Rust is a preserved legacy reference, not the supported mobile runtime.

### II. Spec-Driven And Test-First
Requirements and edge cases precede implementation. Tests fail before behavior
is implemented and then pass focused validation. Explicit clocks, calendar rules,
idempotency, and deterministic fixtures are mandatory. Coverage is a nonblocking
review signal, not a global percentage gate.

### III. Local-First Durability
Local mutations and sync events are atomic. Completion never waits for network.
Restart, migration, rollback, export, account isolation and deletion are tested.
Existing databases remain preserved until import succeeds.

### IV. Honest Health Evidence And Privacy
Never fabricate sensor data or claim tamper-proof anti-cheat. Missing permissions
and samples are unknown. Minimize collection; raw biometric/location data does
not sync by default. Credentials belong in secure stores. Logs exclude secrets
and sensitive health data.

### V. Measured Quality And Release Evidence
Accessibility, localization, lifecycle recovery and visible errors are required.
Performance claims require release-build measurements on physical devices.
Native CI, real health tests, security review, beta, privacy declarations, signing
and store readiness gate release. A scaffold or Rust tests do not satisfy them.

## Tooling And Operations
Pin dependencies and obtain tools only from official upstream sources. Verify
installer checksums/signatures before execution. Do not create worktrees, discard
user changes, commit, or alter shared cloud lifecycle without authorization.

## Governance
The active native release spec/tasks record completed work and remaining gates.
Exceptions require rationale and acceptance evidence. Unconfirmed markets,
accounts, release ownership and dates remain explicit.

Version: 1.0.0 | Adopted: 2026-10-06 | Last Amended: 2026-10-06
