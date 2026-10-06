# SDD Spec 004: Local-First Outbox Sync Protocol (离线优先事件同步协议)

## 1. Principles
- **Local-First**: Every write commits to embedded SQLite synchronously.
- **Outbox Queue**: Mutations create an entry in `sync_outbox` table with an idempotent `event_id` (UUIDv4) and sequence number.
- **Delta Exchange**: When network is connected, the client pushes unacknowledged outbox events and pulls changes since `last_synced_sequence`.
- **Conflict Resolution**: Last-Write-Wins (LWW) based on logical clock and Lamport timestamp for mutable attributes; append-only immutable semantics for check-in records.
