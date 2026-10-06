use dailygo_core::domain::{
    check_in::{CheckInRecord, VerificationStatus},
    habit::{Habit, HabitFrequency, MetricType},
};
use dailygo_core::storage::sqlite_repo::SqliteRepository;

#[test]
fn test_sqlite_in_memory_migrations_and_habit_lifecycle() {
    let repo = SqliteRepository::open_in_memory().expect("Failed to open in-memory database");

    let habit = Habit::new(
        "Evening Yoga".to_string(),
        HabitFrequency::Daily,
        MetricType::DurationMinutes { target: 30 },
    )
    .unwrap();

    let habit_id = habit.id.clone();
    repo.insert_habit(&habit).expect("Failed to insert habit");

    let fetched = repo.get_habit(&habit_id).expect("Failed to query habit");
    assert!(fetched.is_some());
    let fetched_habit = fetched.unwrap();
    assert_eq!(fetched_habit.title, "Evening Yoga");
    assert_eq!(fetched_habit.is_archived, false);

    let active_habits = repo.list_active_habits().expect("Failed to list active habits");
    assert_eq!(active_habits.len(), 1);
    assert_eq!(active_habits[0].id, habit_id);
}

#[test]
fn test_check_in_record_persistence_and_date_queries() {
    let repo = SqliteRepository::open_in_memory().expect("Failed to open in-memory database");

    let habit = Habit::new(
        "Morning Jog".to_string(),
        HabitFrequency::Daily,
        MetricType::DistanceMeters { target: 3000 },
    )
    .unwrap();
    let habit_id = habit.id.clone();
    repo.insert_habit(&habit).unwrap();

    let record1 = CheckInRecord::new(
        habit_id.clone(),
        1790818200000,
        480,
        Some(3100.0),
        VerificationStatus::Verified,
    );
    repo.insert_check_in(&record1).unwrap();

    let record2 = CheckInRecord::new(
        habit_id.clone(),
        1790904600000,
        480,
        Some(3200.0),
        VerificationStatus::Verified,
    );
    repo.insert_check_in(&record2).unwrap();

    let dates = repo.get_check_in_dates_for_habit(&habit_id).unwrap();
    assert_eq!(dates.len(), 2);
    assert!(dates.contains(&record1.local_date));
    assert!(dates.contains(&record2.local_date));

    // Verify outbox entries were recorded for local-first sync
    let outbox = repo.fetch_pending_outbox_events().unwrap();
    // 1 habit creation + 2 check-ins = 3 outbox events
    assert_eq!(outbox.len(), 3);
}
