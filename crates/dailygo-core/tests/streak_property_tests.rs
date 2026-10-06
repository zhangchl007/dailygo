use chrono::NaiveDate;
use dailygo_core::domain::habit::HabitFrequency;
use dailygo_core::state_machine::streak::{calculate_streak, StreakCalculatorConfig};
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_streak_never_exceeds_total_check_ins(
        days_offset in proptest::collection::vec(0i64..100i64, 0..30)
    ) {
        let base_date = NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
        let mut dates: Vec<String> = days_offset
            .into_iter()
            .map(|offset| (base_date + chrono::Duration::days(offset)).format("%Y-%m-%d").to_string())
            .collect();
        dates.sort();
        dates.dedup();

        let today = (base_date + chrono::Duration::days(120)).format("%Y-%m-%d").to_string();
        let config = StreakCalculatorConfig::default();

        let summary = calculate_streak("habit-prop", &dates, &today, &HabitFrequency::Daily, &config);

        prop_assert!(summary.current_streak <= summary.total_check_ins);
        prop_assert!(summary.longest_streak <= summary.total_check_ins);
        prop_assert!(summary.shields_remaining <= config.max_shields);
    }
}
