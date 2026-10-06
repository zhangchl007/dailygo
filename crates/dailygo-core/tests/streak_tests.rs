use dailygo_core::domain::habit::HabitFrequency;
use dailygo_core::state_machine::streak::{calculate_streak, StreakCalculatorConfig};

#[test]
fn test_empty_check_ins_returns_zero_streak() {
    let check_ins: Vec<String> = vec![];
    let today = "2026-10-01";
    let config = StreakCalculatorConfig::default();

    let summary = calculate_streak("habit-1", &check_ins, today, &HabitFrequency::Daily, &config);
    assert_eq!(summary.current_streak, 0);
    assert_eq!(summary.longest_streak, 0);
    assert_eq!(summary.total_check_ins, 0);
    assert!(!summary.is_checked_in_today);
    assert_eq!(summary.shields_remaining, 0);
}

#[test]
fn test_consecutive_daily_streak_increments() {
    let check_ins = vec![
        "2026-09-28".to_string(),
        "2026-09-29".to_string(),
        "2026-09-30".to_string(),
        "2026-10-01".to_string(),
    ];
    let today = "2026-10-01";
    let config = StreakCalculatorConfig::default();

    let summary = calculate_streak("habit-1", &check_ins, today, &HabitFrequency::Daily, &config);
    assert_eq!(summary.current_streak, 4);
    assert_eq!(summary.longest_streak, 4);
    assert_eq!(summary.total_check_ins, 4);
    assert!(summary.is_checked_in_today);
}

#[test]
fn test_streak_maintained_when_today_not_yet_checked_in() {
    let check_ins = vec![
        "2026-09-29".to_string(),
        "2026-09-30".to_string(),
    ];
    let today = "2026-10-01"; // today is not checked in yet, but yesterday was!
    let config = StreakCalculatorConfig::default();

    let summary = calculate_streak("habit-1", &check_ins, today, &HabitFrequency::Daily, &config);
    assert_eq!(summary.current_streak, 2);
    assert!(!summary.is_checked_in_today);
}

#[test]
fn test_streak_resets_if_yesterday_missed_and_no_shields() {
    let check_ins = vec![
        "2026-09-27".to_string(),
        "2026-09-28".to_string(),
        // 2026-09-29 and 2026-09-30 missed!
        "2026-10-01".to_string(),
    ];
    let today = "2026-10-01";
    let config = StreakCalculatorConfig::default();

    let summary = calculate_streak("habit-1", &check_ins, today, &HabitFrequency::Daily, &config);
    assert_eq!(summary.current_streak, 1);
    assert_eq!(summary.longest_streak, 2);
    assert_eq!(summary.total_check_ins, 3);
}

#[test]
fn test_streak_shield_bridges_single_missed_day() {
    // 7 consecutive days: earns 1 shield
    // 2026-09-20 to 2026-09-26 (7 days)
    // 2026-09-27 missed! (shield consumed)
    // 2026-09-28 checked in!
    let check_ins = vec![
        "2026-09-20".to_string(),
        "2026-09-21".to_string(),
        "2026-09-22".to_string(),
        "2026-09-23".to_string(),
        "2026-09-24".to_string(),
        "2026-09-25".to_string(),
        "2026-09-26".to_string(),
        // 2026-09-27 is missed
        "2026-09-28".to_string(),
    ];
    let today = "2026-09-28";
    let config = StreakCalculatorConfig::default();

    let summary = calculate_streak("habit-1", &check_ins, today, &HabitFrequency::Daily, &config);
    // 7 days + 1 bridged + 1 = 8 continuous active streak
    assert_eq!(summary.current_streak, 8);
    assert_eq!(summary.shields_remaining, 0); // shield was consumed
}

#[test]
fn test_duplicate_check_ins_same_day_deduplicated() {
    let check_ins = vec![
        "2026-09-30".to_string(),
        "2026-10-01".to_string(),
        "2026-10-01".to_string(),
        "2026-10-01".to_string(),
    ];
    let today = "2026-10-01";
    let config = StreakCalculatorConfig::default();

    let summary = calculate_streak("habit-1", &check_ins, today, &HabitFrequency::Daily, &config);
    assert_eq!(summary.current_streak, 2);
    assert_eq!(summary.total_check_ins, 2);
}
