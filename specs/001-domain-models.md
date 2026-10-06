# SDD Spec 001: Domain Models (领域模型契约)

## 1. Scope & Objective
This specification formally defines the core domain entities for DailyGo: `Habit`, `CheckInRecord`, `WorkoutSession`, `HealthSnapshot`, and `StreakSummary`.

## 2. Invariants & Definitions

### 2.1 Habit
- `id`: UUID v4 string, immutable.
- `title`: Non-empty string (1..100 utf8 chars).
- `target_frequency`:
  - `Daily`: Every calendar day.
  - `Weekdays`: Monday through Friday.
  - `WeeklyTarget { times_per_week: u32 }`: 1..7 times per week.
- `metric_type`:
  - `Completion`: Boolean check (did it or not).
  - `DurationMinutes { target: u32 }`: e.g., 30 mins.
  - `DistanceMeters { target: u32 }`: e.g., 5000 meters.
  - `Steps { target: u32 }`: e.g., 10000 steps.
- `created_at_utc`: ISO 8601 UTC timestamp.
- `is_archived`: Boolean.

### 2.2 CheckInRecord
- `id`: UUID v4 string.
- `habit_id`: References `Habit.id`.
- `timestamp_utc`: Epoch milliseconds.
- `tz_offset_minutes`: Local timezone offset from UTC (-720..840).
- `local_date`: Normalized YYYY-MM-DD string according to local offset and midnight grace period.
- `value`: Optional numeric value (e.g. actual meters, minutes, steps).
- `verification_status`:
  - `Verified`: Backed by valid sensor data score $\ge 0.7$.
  - `SelfReported`: Manually checked in with no/insufficient sensor evidence.
  - `Suspect`: Sensor evidence directly contradicts claim.
- `sync_status`: `Pending`, `Synced`, `Conflict`.

### 2.3 HealthSnapshot
- Sensor metrics collected during the workout window:
  - `step_delta`: Steps accumulated during window.
  - `avg_heart_rate`: Beats per minute.
  - `max_heart_rate`: Beats per minute.
  - `active_energy_burned_kcal`: Active calories burned.
  - `distance_meters`: Sensor-reported GPS/pedometer distance.
  - `source`: `HealthKit`, `HealthConnect`, `Manual`.
