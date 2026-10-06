use dailygo_core::domain::{
    check_in::VerificationStatus,
    habit::{HabitFrequency, MetricType},
    health::{HealthSnapshot, SensorSource},
};
use dailygo_core::service::engine::DailyGoEngine;
use dailygo_core::storage::sqlite_repo::SqliteRepository;
use std::sync::Arc;

#[test]
fn test_dailygo_engine_check_in_and_streak_workflow() {
    let repo = Arc::new(SqliteRepository::open_in_memory().unwrap());
    let engine = DailyGoEngine::new(repo);

    let habit = engine
        .create_habit(
            "Push-ups Daily".to_string(),
            HabitFrequency::Daily,
            MetricType::Completion,
        )
        .expect("Habit creation failed");

    let habit_id = habit.id.clone();

    // Check in with vigorous workout sensor data
    let snapshot = HealthSnapshot::new(
        1200,
        140.0,
        160.0,
        150.0,
        800.0,
        SensorSource::HealthKit,
    );

    let check_in_res = engine
        .check_in(
            &habit_id,
            Some(30.0),
            Some(snapshot),
            480, // UTC+8
        )
        .expect("Check-in failed");

    assert_eq!(check_in_res.record.habit_id, habit_id);
    assert_eq!(check_in_res.verification.status, VerificationStatus::Verified);

    // Query streak
    let streak = engine.get_streak(&habit_id).expect("Failed to get streak");
    assert_eq!(streak.current_streak, 1);
    assert_eq!(streak.total_check_ins, 1);
    assert!(streak.is_checked_in_today);
}
