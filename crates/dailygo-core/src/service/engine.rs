use std::sync::Arc;
use serde::{Deserialize, Serialize};

use crate::anti_cheat::proof_of_sweat::{
    verify_proof_of_sweat, UserFitnessProfile, VerificationResult,
};
use crate::domain::check_in::CheckInRecord;
use crate::domain::habit::{Habit, HabitFrequency, MetricType};
use crate::domain::health::HealthSnapshot;
use crate::domain::streak::StreakSummary;
use crate::error::DailyGoError;
use crate::state_machine::streak::{calculate_streak, StreakCalculatorConfig};
use crate::storage::sqlite_repo::SqliteRepository;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CheckInResult {
    pub record: CheckInRecord,
    pub verification: VerificationResult,
}

pub struct DailyGoEngine {
    repo: Arc<SqliteRepository>,
    fitness_profile: UserFitnessProfile,
    streak_config: StreakCalculatorConfig,
}

impl DailyGoEngine {
    pub fn new(repo: Arc<SqliteRepository>) -> Self {
        Self {
            repo,
            fitness_profile: UserFitnessProfile::default(),
            streak_config: StreakCalculatorConfig::default(),
        }
    }

    pub fn open_file(path: &str) -> Result<Self, DailyGoError> {
        let repo = Arc::new(SqliteRepository::open(path)?);
        Ok(Self::new(repo))
    }

    pub fn create_habit(
        &self,
        title: String,
        frequency: HabitFrequency,
        metric: MetricType,
    ) -> Result<Habit, DailyGoError> {
        let habit = Habit::new(title, frequency, metric)?;
        self.repo.insert_habit(&habit)?;
        Ok(habit)
    }

    pub fn list_active_habits(&self) -> Result<Vec<Habit>, DailyGoError> {
        self.repo.list_active_habits()
    }

    pub fn check_in(
        &self,
        habit_id: &str,
        value: Option<f64>,
        sensor_data: Option<HealthSnapshot>,
        tz_offset_minutes: i32,
    ) -> Result<CheckInResult, DailyGoError> {
        let habit = self
            .repo
            .get_habit(habit_id)?
            .ok_or_else(|| DailyGoError::HabitNotFound(habit_id.to_string()))?;

        // 1. Run anti-cheat verification
        let verification = verify_proof_of_sweat(
            &habit.metric,
            value,
            sensor_data.as_ref(),
            &self.fitness_profile,
        );

        // 2. Create CheckInRecord
        let now_utc = chrono::Utc::now().timestamp_millis();
        let record = CheckInRecord::new(
            habit_id.to_string(),
            now_utc,
            tz_offset_minutes,
            value,
            verification.status,
        );

        // 3. Save into local SQLite repository
        self.repo.insert_check_in(&record)?;

        Ok(CheckInResult {
            record,
            verification,
        })
    }

    pub fn get_streak(&self, habit_id: &str) -> Result<StreakSummary, DailyGoError> {
        let habit = self
            .repo
            .get_habit(habit_id)?
            .ok_or_else(|| DailyGoError::HabitNotFound(habit_id.to_string()))?;

        let dates = self.repo.get_check_in_dates_for_habit(habit_id)?;
        let today = chrono::Utc::now().format("%Y-%m-%d").to_string();

        let summary = calculate_streak(
            habit_id,
            &dates,
            &today,
            &habit.frequency,
            &self.streak_config,
        );

        Ok(summary)
    }
}
