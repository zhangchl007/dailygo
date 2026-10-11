package com.dailygo.storage

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.execSQL
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.double

data class LegacyIssue(val entityId: String?, val code: String)
data class LegacyImportReport(val imported: Boolean, val issues: List<LegacyIssue>)
internal data class LegacyCandidate(val archive: BackupArchive?, val issues: List<LegacyIssue>)

@Serializable
private data class LegacyHabit(val id: String, val title: String, val frequency: JsonElement, val metric: JsonElement,
    val created_at_utc: Long, val is_archived: Boolean)

@Serializable
private data class LegacyCheckIn(val id: String, val habit_id: String, val timestamp_utc: Long,
    val tz_offset_minutes: Int, val local_date: String, val value: Double?, val verification_status: String, val sync_status: String)

private data class LegacyEvent(val id: String, val kind: String, val entityId: String, val payload: String, val instant: Long, val synced: Boolean)

internal object LegacyImport {
    fun read(path: String, ownerId: String, zones: Map<String, String>, acceptUnverified: Boolean): LegacyCandidate {
        validateIdentity(ownerId)
        val json = Json { encodeDefaults = true }
        val connection = BundledSQLiteDriver().open(path, SQLITE_OPEN_READONLY)
        try {
            connection.execSQL("BEGIN")
            val oldHabits = mutableListOf<LegacyHabit>()
            connection.read("SELECT id,title,frequency_json,metric_json,created_at_utc,is_archived FROM habits ORDER BY id") { statement ->
                require(statement.getLong(5) in 0..1)
                oldHabits.add(LegacyHabit(statement.getText(0), statement.getText(1), json.parseToJsonElement(statement.getText(2)),
                    json.parseToJsonElement(statement.getText(3)), statement.getLong(4), statement.getLong(5) == 1L))
            }
            val oldEntries = mutableListOf<LegacyCheckIn>()
            connection.read("SELECT id,habit_id,timestamp_utc,tz_offset_minutes,local_date,value,verification_status,sync_status FROM check_in_records ORDER BY id") { statement ->
                val offset = statement.getLong(3)
                require(offset in -1080..1080)
                oldEntries.add(LegacyCheckIn(statement.getText(0), statement.getText(1), statement.getLong(2), offset.toInt(),
                    statement.getText(4), if (statement.isNull(5)) null else statement.getDouble(5), statement.getText(6), statement.getText(7)))
            }
            val oldEvents = mutableListOf<LegacyEvent>()
            connection.read("SELECT event_id,entity_type,entity_id,payload_json,created_at_utc,is_synced FROM sync_outbox ORDER BY created_at_utc,event_id") { statement ->
                require(statement.getLong(5) in 0..1)
                oldEvents.add(LegacyEvent(statement.getText(0), statement.getText(1), statement.getText(2), statement.getText(3),
                    statement.getLong(4), statement.getLong(5) == 1L))
            }
            connection.execSQL("COMMIT")
            val issues = oldHabits.filter { zones[it.id] == null }.map { LegacyIssue(it.id, "TIMEZONE_REQUIRED") }.toMutableList()
            oldEntries.forEach { issues.add(LegacyIssue(it.id, "UNVERIFIED_PROVENANCE")) }
            if (oldHabits.any { zones[it.id] == null } || (oldEntries.isNotEmpty() && !acceptUnverified)) return LegacyCandidate(null, issues)
            val habits = oldHabits.map { old ->
                val scheduleKind: String
                val parameter: Int?
                when (old.frequency) {
                    JsonPrimitive("Daily") -> { scheduleKind = "daily"; parameter = null }
                    JsonPrimitive("Weekdays") -> { scheduleKind = "weekdays"; parameter = null }
                    else -> {
                        require(old.frequency.jsonObject.keys == setOf("WeeklyTarget"))
                        val weekly = old.frequency.jsonObject.getValue("WeeklyTarget").jsonObject
                        require(weekly.keys == setOf("times_per_week"))
                        scheduleKind = "weekly"; parameter = weekly.getValue("times_per_week").jsonPrimitive.int
                    }
                }
                val goalKind: String
                val target: Double?
                if (old.metric == JsonPrimitive("Completion")) { goalKind = "completion"; target = null }
                else {
                    val metric = old.metric.jsonObject
                    require(metric.size == 1)
                    goalKind = when (metric.keys.single()) {
                        "Steps" -> "steps"
                        "DurationMinutes" -> "duration_minutes"
                        "DistanceMeters" -> "distance_meters"
                        else -> throw IllegalArgumentException("Unknown legacy metric")
                    }
                    val value = metric.values.single().jsonObject
                    require(value.keys == setOf("target"))
                    target = value.getValue("target").jsonPrimitive.double
                }
                HabitRow(ownerId, old.id, old.title, scheduleKind, parameter, goalKind, target,
                    zones.getValue(old.id), old.created_at_utc, old.is_archived).also { it.definition() }
            }
            val byId = habits.associateBy { it.id }
            val checkIns = mutableListOf<CheckInRow>()
            val progress = mutableListOf<ProgressRow>()
            oldEntries.forEach { old ->
                require(old.verification_status in setOf("Verified", "SelfReported", "Suspect"))
                require(old.sync_status in setOf("Pending", "Synced")) { "Unresolved legacy conflict" }
                val habit = byId.getValue(old.habit_id)
                val zone = ZoneId.of(habit.zoneId)
                require(zone.rules.getOffset(Instant.ofEpochMilli(old.timestamp_utc)).totalSeconds == old.tz_offset_minutes * 60) { "Timezone offset mismatch" }
                if (habit.definition().goal.isCompleted(old.value)) {
                    checkIns.add(CheckInRow(ownerId, old.id, old.habit_id, old.timestamp_utc, old.local_date, habit.zoneId, "LEGACY_IMPORTED", old.value))
                } else {
                    progress.add(ProgressRow(ownerId, old.id, old.habit_id, old.timestamp_utc, old.local_date,
                        habit.zoneId, "LEGACY_IMPORTED", requireNotNull(old.value)))
                }
                if (old.sync_status == "Pending") require(oldEvents.any { it.kind == "CheckInCreated" && it.entityId == old.id }) { "Missing pending change" }
            }
            val events = mutableListOf<OutboxRow>()
            val receipts = mutableListOf<MutationReceiptRow>()
            oldEvents.forEach { old ->
                val kind: String
                val payload: String
                val request: String
                when (old.kind) {
                    "HabitCreated" -> {
                        val source = oldHabits.single { it.id == old.entityId }
                        require(json.decodeFromString<LegacyHabit>(old.payload) == source) { "Legacy payload mismatch" }
                        kind = "habit.created"; payload = json.encodeToString(byId.getValue(old.entityId)); request = payload
                    }
                    "CheckInCreated" -> {
                        val source = oldEntries.single { it.id == old.entityId }
                        require(json.decodeFromString<LegacyCheckIn>(old.payload) == source) { "Legacy payload mismatch" }
                        val completion = checkIns.singleOrNull { it.id == old.entityId }
                        if (completion != null) {
                            kind = "checkin.completed"; payload = json.encodeToString(completion)
                            request = json.encodeToString(CompletionCommand(ownerId, old.id, source.id, source.habit_id, source.timestamp_utc, source.value))
                        } else {
                            val partial = progress.single { it.id == old.entityId }
                            kind = "progress.recorded"; payload = json.encodeToString(partial)
                            request = json.encodeToString(ProgressCommand(ownerId, old.id, source.id, source.habit_id, source.timestamp_utc, partial.value))
                        }
                    }
                    else -> throw IllegalArgumentException("Unsupported pending legacy change")
                }
                receipts.add(MutationReceiptRow(ownerId, old.id, kind, request, old.entityId))
                if (!old.synced) events.add(OutboxRow(ownerId, old.id, kind, old.entityId, payload, old.instant))
            }
            val archive = BackupArchive(ownerId = ownerId, habits = habits, checkIns = checkIns, progress = progress, events = events, receipts = receipts)
            archive.validate(ownerId, json)
            return LegacyCandidate(archive, issues)
        } finally { connection.close() }
    }

    private fun SQLiteConnection.read(sql: String, block: (androidx.sqlite.SQLiteStatement) -> Unit) {
        val statement = prepare(sql)
        try { while (statement.step()) block(statement) } finally { statement.close() }
    }
}