use dailygo_core::domain::{
    check_in::{CheckInRecord, VerificationStatus},
    habit::{Habit, HabitFrequency, MetricType},
    health::{HealthSnapshot, SensorSource},
};

#[test]
fn test_create_habit_validates_title() {
    let empty_title = Habit::new("".to_string(), HabitFrequency::Daily, MetricType::Completion);
    assert!(empty_title.is_err(), "Habit title cannot be empty");

    let valid_habit = Habit::new("Morning 5km Run".to_string(), HabitFrequency::Daily, MetricType::DistanceMeters { target: 5000 });
    assert!(valid_habit.is_ok());
    let habit = valid_habit.unwrap();
    assert_eq!(habit.title, "Morning 5km Run");
    assert!(!habit.is_archived);
}

#[test]
fn test_create_check_in_record_local_date_normalization() {
    let habit_id = "habit-123".to_string();
    
    // 2026-10-01 01:30:00 UTC with UTC+8 offset (+480 min) -> 09:30:00 local date: 2026-10-01
    // timestamp_utc for 2026-10-01 01:30:00 UTC = 1790818200000 ms
    let timestamp_utc = 1790818200000;
    let tz_offset = 480; // UTC+8
    let record = CheckInRecord::new(
        habit_id,
        timestamp_utc,
        tz_offset,
        Some(5200.0),
        VerificationStatus::Verified,
    );

    assert_eq!(record.local_date, "2026-10-01");
    assert_eq!(record.tz_offset_minutes, 480);
    assert_eq!(record.verification_status, VerificationStatus::Verified);
}

#[test]
fn test_health_snapshot_validations() {
    let snapshot = HealthSnapshot::new(
        6200,          // 6200 steps
        145.0,         // avg heart rate
        172.0,         // max heart rate
        340.0,         // active kcal
        5100.0,        // distance in meters
        SensorSource::HealthKit,
    );

    assert_eq!(snapshot.step_delta, 6200);
    assert_eq!(snapshot.source, SensorSource::HealthKit);
}
