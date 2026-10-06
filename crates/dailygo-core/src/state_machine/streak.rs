use std::collections::BTreeSet;
use chrono::NaiveDate;
use crate::domain::habit::HabitFrequency;
use crate::domain::streak::StreakSummary;

#[derive(Debug, Clone)]
pub struct StreakCalculatorConfig {
    pub days_per_shield: u32,
    pub max_shields: u32,
    pub midnight_grace_hours: u32,
}

impl Default for StreakCalculatorConfig {
    fn default() -> Self {
        Self {
            days_per_shield: 7,
            max_shields: 3,
            midnight_grace_hours: 3,
        }
    }
}

pub fn calculate_streak(
    habit_id: &str,
    raw_dates: &[String],
    today_str: &str,
    _frequency: &HabitFrequency,
    config: &StreakCalculatorConfig,
) -> StreakSummary {
    let mut parsed_dates = BTreeSet::new();
    for d in raw_dates {
        if let Ok(date) = NaiveDate::parse_from_str(d, "%Y-%m-%d") {
            parsed_dates.insert(date);
        }
    }

    let today = NaiveDate::parse_from_str(today_str, "%Y-%m-%d")
        .unwrap_or_else(|_| chrono::Utc::now().date_naive());

    if parsed_dates.is_empty() {
        return StreakSummary {
            habit_id: habit_id.to_string(),
            current_streak: 0,
            longest_streak: 0,
            total_check_ins: 0,
            shields_remaining: 0,
            is_checked_in_today: false,
            last_check_in_date: None,
        };
    }

    let is_checked_in_today = parsed_dates.contains(&today);
    let total_check_ins = parsed_dates.len() as u32;
    let last_check_in = *parsed_dates.iter().last().unwrap();

    let mut current_streak = 0;
    let mut longest_streak = 0;
    let mut shields_available = 0;
    let mut consecutive_unshielded = 0;

    let mut prev_date: Option<NaiveDate> = None;

    for date in &parsed_dates {
        match prev_date {
            None => {
                current_streak = 1;
                consecutive_unshielded = 1;
            }
            Some(prev) => {
                let gap = (*date - prev).num_days();
                if gap == 1 {
                    current_streak += 1;
                    consecutive_unshielded += 1;
                    if consecutive_unshielded >= config.days_per_shield {
                        if shields_available < config.max_shields {
                            shields_available += 1;
                        }
                        consecutive_unshielded = 0;
                    }
                } else if gap == 2 && shields_available > 0 {
                    // 1 day missed, consumed 1 shield to bridge gap
                    shields_available -= 1;
                    current_streak += 1;
                    consecutive_unshielded = 0;
                } else {
                    // Gap too large or no shields, streak resets
                    current_streak = 1;
                    consecutive_unshielded = 1;
                }
            }
        }

        if current_streak > longest_streak {
            longest_streak = current_streak;
        }

        prev_date = Some(*date);
    }

    // Now evaluate current streak against `today`:
    // If last check in was today: current_streak is active.
    // If last check in was yesterday: today not yet checked in, current_streak is still intact.
    // If last check in was 2 days ago: if shield available, it can still be preserved, otherwise broken.
    let gap_from_today = (today - last_check_in).num_days();
    let effective_current_streak = if gap_from_today == 0 || gap_from_today == 1 {
        current_streak
    } else if gap_from_today == 2 && shields_available > 0 {
        current_streak
    } else {
        0
    };

    StreakSummary {
        habit_id: habit_id.to_string(),
        current_streak: effective_current_streak,
        longest_streak,
        total_check_ins,
        shields_remaining: shields_available,
        is_checked_in_today,
        last_check_in_date: Some(last_check_in.format("%Y-%m-%d").to_string()),
    }
}
