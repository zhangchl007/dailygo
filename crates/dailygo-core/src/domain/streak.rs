use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StreakSummary {
    pub habit_id: String,
    pub current_streak: u32,
    pub longest_streak: u32,
    pub total_check_ins: u32,
    pub shields_remaining: u32,
    pub is_checked_in_today: bool,
    pub last_check_in_date: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HeatMapDay {
    pub date: String, // YYYY-MM-DD
    pub count: u32,
    pub verified_count: u32,
}
