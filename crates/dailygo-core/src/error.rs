use thiserror::Error;

#[derive(Error, Debug, PartialEq)]
pub enum DailyGoError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Storage error: {0}")]
    StorageError(String),

    #[error("Habit not found with id: {0}")]
    HabitNotFound(String),

    #[error("AntiCheat rejected check-in: {0}")]
    AntiCheatRejected(String),

    #[error("Sync conflict error: {0}")]
    SyncConflict(String),
}
