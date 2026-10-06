use std::sync::Arc;
use dailygo_core::domain::check_in::{CheckInRecord, VerificationStatus};
use dailygo_core::domain::habit::{Habit, HabitFrequency, MetricType};
use dailygo_core::domain::health::{HealthSnapshot, SensorSource};
use dailygo_core::domain::streak::StreakSummary;
use dailygo_core::service::engine::DailyGoEngine;
use dailygo_core::storage::sqlite_repo::SqliteRepository;
use thiserror::Error;

uniffi::setup_scaffolding!();

#[derive(Error, Debug, uniffi::Error)]
pub enum DailyGoFfiError {
    #[error("Validation failed: {message}")]
    ValidationError { message: String },
    #[error("Storage error: {message}")]
    StorageError { message: String },
    #[error("Habit not found: {id}")]
    HabitNotFound { id: String },
    #[error("Anti-cheat error: {message}")]
    AntiCheatError { message: String },
}

impl From<dailygo_core::DailyGoError> for DailyGoFfiError {
    fn from(err: dailygo_core::DailyGoError) -> Self {
        match err {
            dailygo_core::DailyGoError::ValidationError(m) => {
                DailyGoFfiError::ValidationError { message: m }
            }
            dailygo_core::DailyGoError::StorageError(m) => {
                DailyGoFfiError::StorageError { message: m }
            }
            dailygo_core::DailyGoError::HabitNotFound(id) => {
                DailyGoFfiError::HabitNotFound { id }
            }
            dailygo_core::DailyGoError::AntiCheatRejected(m) => {
                DailyGoFfiError::AntiCheatError { message: m }
            }
            dailygo_core::DailyGoError::SyncConflict(m) => {
                DailyGoFfiError::StorageError { message: m }
            }
        }
    }
}

#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum HabitFrequencyFfi {
    Daily,
    Weekdays,
    WeeklyTarget { times_per_week: u32 },
}

impl From<HabitFrequencyFfi> for HabitFrequency {
    fn from(f: HabitFrequencyFfi) -> Self {
        match f {
            HabitFrequencyFfi::Daily => HabitFrequency::Daily,
            HabitFrequencyFfi::Weekdays => HabitFrequency::Weekdays,
            HabitFrequencyFfi::WeeklyTarget { times_per_week } => {
                HabitFrequency::WeeklyTarget { times_per_week }
            }
        }
    }
}

impl From<HabitFrequency> for HabitFrequencyFfi {
    fn from(f: HabitFrequency) -> Self {
        match f {
            HabitFrequency::Daily => HabitFrequencyFfi::Daily,
            HabitFrequency::Weekdays => HabitFrequencyFfi::Weekdays,
            HabitFrequency::WeeklyTarget { times_per_week } => {
                HabitFrequencyFfi::WeeklyTarget { times_per_week }
            }
        }
    }
}

#[derive(uniffi::Enum, Clone, Debug, PartialEq)]
pub enum MetricTypeFfi {
    Completion,
    DurationMinutes { target: u32 },
    DistanceMeters { target: u32 },
    Steps { target: u32 },
}

impl From<MetricTypeFfi> for MetricType {
    fn from(m: MetricTypeFfi) -> Self {
        match m {
            MetricTypeFfi::Completion => MetricType::Completion,
            MetricTypeFfi::DurationMinutes { target } => MetricType::DurationMinutes { target },
            MetricTypeFfi::DistanceMeters { target } => MetricType::DistanceMeters { target },
            MetricTypeFfi::Steps { target } => MetricType::Steps { target },
        }
    }
}

impl From<MetricType> for MetricTypeFfi {
    fn from(m: MetricType) -> Self {
        match m {
            MetricType::Completion => MetricTypeFfi::Completion,
            MetricType::DurationMinutes { target } => MetricTypeFfi::DurationMinutes { target },
            MetricType::DistanceMeters { target } => MetricTypeFfi::DistanceMeters { target },
            MetricType::Steps { target } => MetricTypeFfi::Steps { target },
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum VerificationStatusFfi {
    Verified,
    SelfReported,
    Suspect,
}

impl From<VerificationStatus> for VerificationStatusFfi {
    fn from(s: VerificationStatus) -> Self {
        match s {
            VerificationStatus::Verified => VerificationStatusFfi::Verified,
            VerificationStatus::SelfReported => VerificationStatusFfi::SelfReported,
            VerificationStatus::Suspect => VerificationStatusFfi::Suspect,
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SensorSourceFfi {
    HealthKit,
    HealthConnect,
    Manual,
}

impl From<SensorSourceFfi> for SensorSource {
    fn from(s: SensorSourceFfi) -> Self {
        match s {
            SensorSourceFfi::HealthKit => SensorSource::HealthKit,
            SensorSourceFfi::HealthConnect => SensorSource::HealthConnect,
            SensorSourceFfi::Manual => SensorSource::Manual,
        }
    }
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct HealthSnapshotFfi {
    pub step_delta: u32,
    pub avg_heart_rate: f64,
    pub max_heart_rate: f64,
    pub active_energy_burned_kcal: f64,
    pub distance_meters: f64,
    pub source: SensorSourceFfi,
}

impl From<HealthSnapshotFfi> for HealthSnapshot {
    fn from(h: HealthSnapshotFfi) -> Self {
        HealthSnapshot {
            step_delta: h.step_delta,
            avg_heart_rate: h.avg_heart_rate,
            max_heart_rate: h.max_heart_rate,
            active_energy_burned_kcal: h.active_energy_burned_kcal,
            distance_meters: h.distance_meters,
            source: h.source.into(),
        }
    }
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct HabitFfi {
    pub id: String,
    pub title: String,
    pub frequency: HabitFrequencyFfi,
    pub metric: MetricTypeFfi,
    pub created_at_utc: i64,
    pub is_archived: bool,
}

impl From<Habit> for HabitFfi {
    fn from(h: Habit) -> Self {
        Self {
            id: h.id,
            title: h.title,
            frequency: h.frequency.into(),
            metric: h.metric.into(),
            created_at_utc: h.created_at_utc,
            is_archived: h.is_archived,
        }
    }
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct CheckInRecordFfi {
    pub id: String,
    pub habit_id: String,
    pub timestamp_utc: i64,
    pub tz_offset_minutes: i32,
    pub local_date: String,
    pub value: Option<f64>,
    pub verification_status: VerificationStatusFfi,
}

impl From<CheckInRecord> for CheckInRecordFfi {
    fn from(r: CheckInRecord) -> Self {
        Self {
            id: r.id,
            habit_id: r.habit_id,
            timestamp_utc: r.timestamp_utc,
            tz_offset_minutes: r.tz_offset_minutes,
            local_date: r.local_date,
            value: r.value,
            verification_status: r.verification_status.into(),
        }
    }
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StreakSummaryFfi {
    pub habit_id: String,
    pub current_streak: u32,
    pub longest_streak: u32,
    pub total_check_ins: u32,
    pub shields_remaining: u32,
    pub is_checked_in_today: bool,
    pub last_check_in_date: Option<String>,
}

impl From<StreakSummary> for StreakSummaryFfi {
    fn from(s: StreakSummary) -> Self {
        Self {
            habit_id: s.habit_id,
            current_streak: s.current_streak,
            longest_streak: s.longest_streak,
            total_check_ins: s.total_check_ins,
            shields_remaining: s.shields_remaining,
            is_checked_in_today: s.is_checked_in_today,
            last_check_in_date: s.last_check_in_date,
        }
    }
}

#[derive(uniffi::Object)]
pub struct DailyGoEngineFfi {
    inner: DailyGoEngine,
}

#[uniffi::export]
impl DailyGoEngineFfi {
    pub fn create_habit(
        &self,
        title: String,
        frequency: HabitFrequencyFfi,
        metric: MetricTypeFfi,
    ) -> Result<HabitFfi, DailyGoFfiError> {
        let habit = self
            .inner
            .create_habit(title, frequency.into(), metric.into())?;
        Ok(habit.into())
    }

    pub fn list_active_habits(&self) -> Result<Vec<HabitFfi>, DailyGoFfiError> {
        let habits = self.inner.list_active_habits()?;
        Ok(habits.into_iter().map(Into::into).collect())
    }

    pub fn check_in(
        &self,
        habit_id: String,
        value: Option<f64>,
        sensor_data: Option<HealthSnapshotFfi>,
        tz_offset_minutes: i32,
    ) -> Result<CheckInRecordFfi, DailyGoFfiError> {
        let snapshot = sensor_data.map(Into::into);
        let res = self
            .inner
            .check_in(&habit_id, value, snapshot, tz_offset_minutes)?;
        Ok(res.record.into())
    }

    pub fn get_streak(&self, habit_id: String) -> Result<StreakSummaryFfi, DailyGoFfiError> {
        let streak = self.inner.get_streak(&habit_id)?;
        Ok(streak.into())
    }
}

#[uniffi::export]
pub fn create_engine(db_path: String) -> Result<Arc<DailyGoEngineFfi>, DailyGoFfiError> {
    let engine = DailyGoEngine::open_file(&db_path)?;
    Ok(Arc::new(DailyGoEngineFfi { inner: engine }))
}

#[uniffi::export]
pub fn create_in_memory_engine() -> Result<Arc<DailyGoEngineFfi>, DailyGoFfiError> {
    let repo = Arc::new(SqliteRepository::open_in_memory()?);
    let engine = DailyGoEngine::new(repo);
    Ok(Arc::new(DailyGoEngineFfi { inner: engine }))
}
