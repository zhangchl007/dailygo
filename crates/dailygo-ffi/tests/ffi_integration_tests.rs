use dailygo_ffi::{
    create_in_memory_engine, HabitFrequencyFfi, HealthSnapshotFfi, MetricTypeFfi, SensorSourceFfi,
    VerificationStatusFfi,
};

#[test]
fn test_uniffi_exported_engine_lifecycle() {
    let engine = create_in_memory_engine().expect("Failed to create in-memory FFI engine");

    let habit = engine
        .create_habit(
            "100 Squats".to_string(),
            HabitFrequencyFfi::Daily,
            MetricTypeFfi::Steps { target: 100 },
        )
        .expect("FFI create habit failed");

    assert_eq!(habit.title, "100 Squats");

    let active_habits = engine.list_active_habits().expect("FFI list habits failed");
    assert_eq!(active_habits.len(), 1);

    let snapshot = HealthSnapshotFfi {
        step_delta: 200,
        avg_heart_rate: 135.0,
        max_heart_rate: 155.0,
        active_energy_burned_kcal: 85.0,
        distance_meters: 150.0,
        source: SensorSourceFfi::HealthKit,
    };

    let check_in = engine
        .check_in(
            habit.id.clone(),
            Some(100.0),
            Some(snapshot),
            480, // UTC+8
        )
        .expect("FFI check_in failed");

    assert_eq!(check_in.habit_id, habit.id);
    assert_eq!(check_in.verification_status, VerificationStatusFfi::Verified);

    let streak = engine.get_streak(habit.id).expect("FFI get_streak failed");
    assert_eq!(streak.current_streak, 1);
    assert_eq!(streak.total_check_ins, 1);
    assert!(streak.is_checked_in_today);
}
