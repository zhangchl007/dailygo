use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::error::DailyGoError;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum HabitFrequency {
    Daily,
    Weekdays,
    WeeklyTarget { times_per_week: u32 },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum MetricType {
    Completion,
    DurationMinutes { target: u32 },
    DistanceMeters { target: u32 },
    Steps { target: u32 },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Habit {
    pub id: String,
    pub title: String,
    pub frequency: HabitFrequency,
    pub metric: MetricType,
    pub created_at_utc: i64,
    pub is_archived: bool,
}

impl Habit {
    pub fn new(
        title: String,
        frequency: HabitFrequency,
        metric: MetricType,
    ) -> Result<Self, DailyGoError> {
        let trimmed = title.trim();
        if trimmed.is_empty() {
            return Err(DailyGoError::ValidationError(
                "Habit title cannot be empty".to_string(),
            ));
        }

        if let HabitFrequency::WeeklyTarget { times_per_week } = frequency {
            if !(1..=7).contains(&times_per_week) {
                return Err(DailyGoError::ValidationError(
                    "Weekly target must be between 1 and 7".to_string(),
                ));
            }
        }

        let now_utc = chrono::Utc::now().timestamp_millis();

        Ok(Self {
            id: Uuid::new_v4().to_string(),
            title: trimmed.to_string(),
            frequency,
            metric,
            created_at_utc: now_utc,
            is_archived: false,
        })
    }
}
