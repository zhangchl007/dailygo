use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VerificationStatus {
    Verified,
    SelfReported,
    Suspect,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SyncStatus {
    Pending,
    Synced,
    Conflict,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CheckInRecord {
    pub id: String,
    pub habit_id: String,
    pub timestamp_utc: i64,
    pub tz_offset_minutes: i32,
    pub local_date: String, // YYYY-MM-DD
    pub value: Option<f64>,
    pub verification_status: VerificationStatus,
    pub sync_status: SyncStatus,
}

impl CheckInRecord {
    pub fn new(
        habit_id: String,
        timestamp_utc: i64,
        tz_offset_minutes: i32,
        value: Option<f64>,
        verification_status: VerificationStatus,
    ) -> Self {
        let local_date = Self::compute_local_date(timestamp_utc, tz_offset_minutes);

        Self {
            id: Uuid::new_v4().to_string(),
            habit_id,
            timestamp_utc,
            tz_offset_minutes,
            local_date,
            value,
            verification_status,
            sync_status: SyncStatus::Pending,
        }
    }

    pub fn compute_local_date(timestamp_utc: i64, tz_offset_minutes: i32) -> String {
        let utc_dt = DateTime::from_timestamp_millis(timestamp_utc).unwrap_or_else(|| Utc::now());
        let local_dt = utc_dt + Duration::minutes(tz_offset_minutes as i64);
        local_dt.format("%Y-%m-%d").to_string()
    }
}
