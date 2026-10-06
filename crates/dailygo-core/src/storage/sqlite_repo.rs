use std::sync::Mutex;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::domain::check_in::{CheckInRecord, SyncStatus, VerificationStatus};
use crate::domain::habit::{Habit, HabitFrequency, MetricType};
use crate::error::DailyGoError;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OutboxEvent {
    pub event_id: String,
    pub entity_type: String,
    pub entity_id: String,
    pub payload_json: String,
    pub created_at_utc: i64,
}

pub struct SqliteRepository {
    conn: Mutex<Connection>,
}

impl SqliteRepository {
    pub fn open(path: &str) -> Result<Self, DailyGoError> {
        let conn = Connection::open(path)
            .map_err(|e| DailyGoError::StorageError(format!("Failed to open db: {}", e)))?;
        let repo = Self {
            conn: Mutex::new(conn),
        };
        repo.run_migrations()?;
        Ok(repo)
    }

    pub fn open_in_memory() -> Result<Self, DailyGoError> {
        let conn = Connection::open_in_memory()
            .map_err(|e| DailyGoError::StorageError(format!("Failed to open in-memory db: {}", e)))?;
        let repo = Self {
            conn: Mutex::new(conn),
        };
        repo.run_migrations()?;
        Ok(repo)
    }

    fn run_migrations(&self) -> Result<(), DailyGoError> {
        let conn = self.conn.lock().unwrap();

        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS habits (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                frequency_json TEXT NOT NULL,
                metric_json TEXT NOT NULL,
                created_at_utc INTEGER NOT NULL,
                is_archived INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS check_in_records (
                id TEXT PRIMARY KEY,
                habit_id TEXT NOT NULL,
                timestamp_utc INTEGER NOT NULL,
                tz_offset_minutes INTEGER NOT NULL,
                local_date TEXT NOT NULL,
                value REAL,
                verification_status TEXT NOT NULL,
                sync_status TEXT NOT NULL,
                FOREIGN KEY (habit_id) REFERENCES habits(id)
            );

            CREATE INDEX IF NOT EXISTS idx_check_ins_habit_date 
            ON check_in_records(habit_id, local_date);

            CREATE TABLE IF NOT EXISTS sync_outbox (
                event_id TEXT PRIMARY KEY,
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                created_at_utc INTEGER NOT NULL,
                is_synced INTEGER NOT NULL DEFAULT 0
            );
            "#,
        )
        .map_err(|e| DailyGoError::StorageError(format!("Migration failed: {}", e)))?;

        Ok(())
    }

    pub fn insert_habit(&self, habit: &Habit) -> Result<(), DailyGoError> {
        let conn = self.conn.lock().unwrap();

        let freq_json = serde_json::to_string(&habit.frequency)
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;
        let metric_json = serde_json::to_string(&habit.metric)
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;
        let habit_payload = serde_json::to_string(habit)
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        conn.execute(
            r#"
            INSERT INTO habits (id, title, frequency_json, metric_json, created_at_utc, is_archived)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            "#,
            params![
                habit.id,
                habit.title,
                freq_json,
                metric_json,
                habit.created_at_utc,
                if habit.is_archived { 1 } else { 0 }
            ],
        )
        .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        // Write outbox event for sync
        let event_id = Uuid::new_v4().to_string();
        let now = chrono::Utc::now().timestamp_millis();
        conn.execute(
            r#"
            INSERT INTO sync_outbox (event_id, entity_type, entity_id, payload_json, created_at_utc, is_synced)
            VALUES (?1, 'HabitCreated', ?2, ?3, ?4, 0)
            "#,
            params![event_id, habit.id, habit_payload, now],
        )
        .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        Ok(())
    }

    pub fn get_habit(&self, id: &str) -> Result<Option<Habit>, DailyGoError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, title, frequency_json, metric_json, created_at_utc, is_archived
                FROM habits WHERE id = ?1
                "#,
            )
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        let mut rows = stmt
            .query(params![id])
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        if let Some(row) = rows.next().map_err(|e| DailyGoError::StorageError(e.to_string()))? {
            let id: String = row.get(0).map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let title: String = row.get(1).map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let freq_json: String = row.get(2).map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let metric_json: String = row.get(3).map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let created_at_utc: i64 = row.get(4).map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let is_archived_int: i32 = row.get(5).map_err(|e| DailyGoError::StorageError(e.to_string()))?;

            let frequency: HabitFrequency = serde_json::from_str(&freq_json)
                .map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let metric: MetricType = serde_json::from_str(&metric_json)
                .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

            Ok(Some(Habit {
                id,
                title,
                frequency,
                metric,
                created_at_utc,
                is_archived: is_archived_int != 0,
            }))
        } else {
            Ok(None)
        }
    }

    pub fn list_active_habits(&self) -> Result<Vec<Habit>, DailyGoError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, title, frequency_json, metric_json, created_at_utc, is_archived
                FROM habits WHERE is_archived = 0 ORDER BY created_at_utc ASC
                "#,
            )
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        let habit_iter = stmt
            .query_map([], |row| {
                let id: String = row.get(0)?;
                let title: String = row.get(1)?;
                let freq_json: String = row.get(2)?;
                let metric_json: String = row.get(3)?;
                let created_at_utc: i64 = row.get(4)?;
                let is_archived_int: i32 = row.get(5)?;
                Ok((id, title, freq_json, metric_json, created_at_utc, is_archived_int))
            })
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        let mut habits = Vec::new();
        for item in habit_iter {
            let (id, title, freq_json, metric_json, created_at_utc, is_archived_int) =
                item.map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let frequency: HabitFrequency = serde_json::from_str(&freq_json)
                .map_err(|e| DailyGoError::StorageError(e.to_string()))?;
            let metric: MetricType = serde_json::from_str(&metric_json)
                .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

            habits.push(Habit {
                id,
                title,
                frequency,
                metric,
                created_at_utc,
                is_archived: is_archived_int != 0,
            });
        }

        Ok(habits)
    }

    pub fn insert_check_in(&self, record: &CheckInRecord) -> Result<(), DailyGoError> {
        let conn = self.conn.lock().unwrap();

        let v_status_str = match record.verification_status {
            VerificationStatus::Verified => "Verified",
            VerificationStatus::SelfReported => "SelfReported",
            VerificationStatus::Suspect => "Suspect",
        };
        let s_status_str = match record.sync_status {
            SyncStatus::Pending => "Pending",
            SyncStatus::Synced => "Synced",
            SyncStatus::Conflict => "Conflict",
        };

        conn.execute(
            r#"
            INSERT INTO check_in_records (
                id, habit_id, timestamp_utc, tz_offset_minutes, local_date, value, verification_status, sync_status
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            "#,
            params![
                record.id,
                record.habit_id,
                record.timestamp_utc,
                record.tz_offset_minutes,
                record.local_date,
                record.value,
                v_status_str,
                s_status_str,
            ],
        )
        .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        // Outbox event
        let event_id = Uuid::new_v4().to_string();
        let payload = serde_json::to_string(record)
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;
        let now = chrono::Utc::now().timestamp_millis();

        conn.execute(
            r#"
            INSERT INTO sync_outbox (event_id, entity_type, entity_id, payload_json, created_at_utc, is_synced)
            VALUES (?1, 'CheckInCreated', ?2, ?3, ?4, 0)
            "#,
            params![event_id, record.id, payload, now],
        )
        .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        Ok(())
    }

    pub fn get_check_in_dates_for_habit(&self, habit_id: &str) -> Result<Vec<String>, DailyGoError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare(
                r#"
                SELECT DISTINCT local_date
                FROM check_in_records
                WHERE habit_id = ?1
                ORDER BY local_date ASC
                "#,
            )
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        let rows = stmt
            .query_map(params![habit_id], |row| row.get::<_, String>(0))
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        let mut dates = Vec::new();
        for r in rows {
            dates.push(r.map_err(|e| DailyGoError::StorageError(e.to_string()))?);
        }

        Ok(dates)
    }

    pub fn fetch_pending_outbox_events(&self) -> Result<Vec<OutboxEvent>, DailyGoError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn
            .prepare(
                r#"
                SELECT event_id, entity_type, entity_id, payload_json, created_at_utc
                FROM sync_outbox
                WHERE is_synced = 0
                ORDER BY created_at_utc ASC
                "#,
            )
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        let rows = stmt
            .query_map([], |row| {
                Ok(OutboxEvent {
                    event_id: row.get(0)?,
                    entity_type: row.get(1)?,
                    entity_id: row.get(2)?,
                    payload_json: row.get(3)?,
                    created_at_utc: row.get(4)?,
                })
            })
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;

        let mut events = Vec::new();
        for r in rows {
            events.push(r.map_err(|e| DailyGoError::StorageError(e.to_string()))?);
        }

        Ok(events)
    }

    pub fn mark_outbox_synced(&self, event_ids: &[String]) -> Result<(), DailyGoError> {
        let conn = self.conn.lock().unwrap();
        for id in event_ids {
            conn.execute(
                "UPDATE sync_outbox SET is_synced = 1 WHERE event_id = ?1",
                params![id],
            )
            .map_err(|e| DailyGoError::StorageError(e.to_string()))?;
        }
        Ok(())
    }
}
