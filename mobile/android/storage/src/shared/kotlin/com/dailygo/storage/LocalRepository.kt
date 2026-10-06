package com.dailygo.storage

import androidx.room.immediateTransaction
import androidx.room.useWriterConnection
import com.dailygo.domain.CalendarPolicy
import com.dailygo.domain.Goal
import com.dailygo.domain.HabitDefinition
import com.dailygo.domain.MetricKind
import com.dailygo.domain.Schedule
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withContext

class LocalRepository(private val database: LocalDatabase) {
    private val ledger = database.ledger()
    private val json = Json { encodeDefaults = true }

    suspend fun importLegacy(path: String, ownerId: String, zones: Map<String, String>, acceptUnverified: Boolean): LegacyImportReport {
        val candidate = try { withContext(Dispatchers.IO) { LegacyImport.read(path, ownerId, zones, acceptUnverified) } }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { return LegacyImportReport(false, listOf(LegacyIssue(null, "INVALID_LEGACY_SOURCE"))) }
        val archive = candidate.archive ?: return LegacyImportReport(false, candidate.issues)
        try { importOwner(ownerId, json.encodeToString(archive)) }
        catch (_: IllegalArgumentException) { return LegacyImportReport(false, candidate.issues + LegacyIssue(null, "TARGET_CONFLICT")) }
        return LegacyImportReport(true, candidate.issues)
    }

    suspend fun exportOwner(ownerId: String): String {
        validateIdentity(ownerId)
        return database.useWriterConnection { connection ->
            connection.immediateTransaction {
                require(!ledger.isDeleted(ownerId)) { "Owner was deleted" }
                val archive = BackupArchive(ownerId = ownerId, habits = ledger.habits(ownerId),
                    checkIns = ledger.allCheckIns(ownerId), progress = ledger.allProgress(ownerId),
                    events = ledger.outbox(ownerId), receipts = ledger.allReceipts(ownerId))
                archive.validate(ownerId, json)
                json.encodeToString(archive).also { require(it.toByteArray(Charsets.UTF_8).size <= 32 * 1024 * 1024) { "Backup too large" } }
            }
        }
    }

    suspend fun importOwner(ownerId: String, contents: String) {
        require(contents.toByteArray(Charsets.UTF_8).size <= 32 * 1024 * 1024) { "Backup too large" }
        val archive = withContext(Dispatchers.IO) {
            json.decodeFromString<BackupArchive>(contents).also { it.validate(ownerId, json) }
        }
        database.useWriterConnection { connection ->
            connection.immediateTransaction {
                require(!ledger.isDeleted(ownerId)) { "Owner was deleted" }
                archive.habits.forEach { record ->
                    val existing = ledger.habit(ownerId, record.id)
                    require(existing == null || existing == record) { "Habit conflict" }
                    if (existing == null) ledger.insertHabit(record)
                }
                archive.checkIns.forEach { record ->
                    val existing = ledger.checkIn(ownerId, record.id)
                    require(existing == null || existing == record) { "Check-in conflict" }
                    if (existing == null) ledger.insertCheckIn(record)
                }
                archive.progress.forEach { record ->
                    val existing = ledger.progress(ownerId, record.id)
                    require(existing == null || existing == record) { "Progress conflict" }
                    if (existing == null) ledger.insertProgress(record)
                }
                val existingEvents = ledger.outbox(ownerId).associateBy { it.eventId }
                archive.events.forEach { record ->
                    val existing = existingEvents[record.eventId]
                    require(existing == null || existing == record) { "Event conflict" }
                    if (existing == null && ledger.receipt(ownerId, record.eventId) == null) ledger.insertOutbox(record)
                }
                archive.receipts.forEach { record ->
                    val existing = ledger.receipt(ownerId, record.operationId)
                    require(existing == null || existing == record) { "Receipt conflict" }
                    if (existing == null) ledger.insertReceipt(record)
                }
            }
        }
    }

    suspend fun deleteOwner(ownerId: String) {
        validateIdentity(ownerId)
        database.useWriterConnection { connection ->
            connection.immediateTransaction {
                if (!ledger.isDeleted(ownerId)) {
                    ledger.deleteHabits(ownerId)
                    ledger.deleteEvents(ownerId)
                    ledger.deleteReceipts(ownerId)
                    ledger.insertDeletedOwner(DeletedOwnerRow(ownerId))
                }
            }
        }
    }

    suspend fun saveHabit(habit: HabitRow, operationId: String): HabitRow {
        validateIdentity(habit.ownerId, habit.id, operationId)
        habit.definition()
        val request = json.encodeToString(habit)
        return database.useWriterConnection { connection ->
            connection.immediateTransaction {
                require(!ledger.isDeleted(habit.ownerId)) { "Owner was deleted" }
                val previous = ledger.receipt(habit.ownerId, operationId)
                if (previous != null) {
                    require(previous.kind == "habit.created" && previous.request == request) { "Operation ID conflict" }
                    return@immediateTransaction requireNotNull(ledger.habit(habit.ownerId, previous.resultId))
                }
                ledger.insertHabit(habit)
                ledger.insertOutbox(OutboxRow(habit.ownerId, operationId, "habit.created", habit.id, request, habit.createdAtMillis))
                ledger.insertReceipt(MutationReceiptRow(habit.ownerId, operationId, "habit.created", request, habit.id))
                habit
            }
        }
    }

    suspend fun setHabitArchived(command: HabitArchiveCommand): HabitRow {
        validateIdentity(command.ownerId, command.operationId, command.habitId)
        require(command.occurredAtMillis <= command.asOfMillis) { "Future habit change" }
        val kind = if (command.archived) "habit.archived" else "habit.restored"
        val request = json.encodeToString(command.copy(asOfMillis = command.occurredAtMillis))
        return database.useWriterConnection { connection ->
            connection.immediateTransaction {
                require(!ledger.isDeleted(command.ownerId)) { "Owner was deleted" }
                val previous = ledger.receipt(command.ownerId, command.operationId)
                if (previous != null) {
                    require(previous.kind == kind && previous.request == request) { "Operation ID conflict" }
                    return@immediateTransaction requireNotNull(ledger.habit(command.ownerId, previous.resultId))
                }
                val habit = requireNotNull(ledger.habit(command.ownerId, command.habitId)) { "Habit not found" }
                require(command.occurredAtMillis >= habit.createdAtMillis) { "Change precedes habit creation" }
                val updated = habit.copy(archived = command.archived)
                require(ledger.updateHabit(updated) == 1) { "Habit not found" }
                ledger.insertOutbox(OutboxRow(command.ownerId, command.operationId, kind, command.habitId, request, command.occurredAtMillis))
                ledger.insertReceipt(MutationReceiptRow(command.ownerId, command.operationId, kind, request, command.habitId))
                updated
            }
        }
    }

    suspend fun recordProgress(command: ProgressCommand): ProgressRow {
        validateIdentity(command.ownerId, command.operationId, command.recordId, command.habitId)
        require(command.occurredAtMillis <= command.asOfMillis) { "Future progress" }
        require(command.value.isFinite() && command.value >= 0) { "Invalid progress" }
        val request = json.encodeToString(command.copy(asOfMillis = command.occurredAtMillis))
        return database.useWriterConnection { connection ->
            connection.immediateTransaction {
                require(!ledger.isDeleted(command.ownerId)) { "Owner was deleted" }
                val previous = ledger.receipt(command.ownerId, command.operationId)
                if (previous != null) {
                    require(previous.kind == "progress.recorded" && previous.request == request) { "Operation ID conflict" }
                    return@immediateTransaction requireNotNull(ledger.progress(command.ownerId, previous.resultId))
                }
                val habit = requireNotNull(ledger.habit(command.ownerId, command.habitId)) { "Habit not found" }
                val definition = habit.definition()
                require(!habit.archived && habit.goalKind != "completion") { "Progress requires an active numeric habit" }
                require(!definition.goal.isCompleted(command.value)) { "Use completion for a reached goal" }
                val occurred = Instant.ofEpochMilli(command.occurredAtMillis)
                val yesterday = occurred.atZone(ZoneId.of(habit.zoneId)).toLocalDate().minusDays(1).toString()
                val credit = CalendarPolicy.credit(
                    occurred, habit.zoneId, command.workoutStartedAtMillis?.let(Instant::ofEpochMilli),
                    previousComplete = ledger.completionOn(command.ownerId, command.habitId, yesterday) != null,
                )
                val record = ProgressRow(
                    command.ownerId, command.recordId, command.habitId, command.occurredAtMillis,
                    credit.date.toString(), credit.zoneId, credit.reason.name, command.value,
                )
                ledger.insertProgress(record)
                ledger.insertOutbox(OutboxRow(
                    command.ownerId, command.operationId, "progress.recorded", record.id,
                    json.encodeToString(record), command.occurredAtMillis,
                ))
                ledger.insertReceipt(MutationReceiptRow(command.ownerId, command.operationId, "progress.recorded", request, record.id))
                record
            }
        }
    }

    suspend fun complete(command: CompletionCommand): CheckInRow {
        validateIdentity(command.ownerId, command.operationId, command.recordId, command.habitId)
        require(command.occurredAtMillis <= command.asOfMillis) { "Future check-in" }
        val request = json.encodeToString(command.copy(asOfMillis = command.occurredAtMillis))
        return database.useWriterConnection { connection ->
            connection.immediateTransaction {
                require(!ledger.isDeleted(command.ownerId)) { "Owner was deleted" }
                val previous = ledger.receipt(command.ownerId, command.operationId)
                if (previous != null) {
                    require(previous.kind == "checkin.completed" && previous.request == request) { "Operation ID conflict" }
                    return@immediateTransaction requireNotNull(ledger.checkIn(command.ownerId, previous.resultId))
                }
                val habit = requireNotNull(ledger.habit(command.ownerId, command.habitId)) { "Habit not found" }
                require(habit.definition().isCompleted(command.value)) { "Goal not completed" }
                val occurred = Instant.ofEpochMilli(command.occurredAtMillis)
                val yesterday = occurred.atZone(ZoneId.of(habit.zoneId)).toLocalDate().minusDays(1).toString()
                val credit = CalendarPolicy.credit(
                    occurred, habit.zoneId, command.workoutStartedAtMillis?.let(Instant::ofEpochMilli),
                    previousComplete = ledger.completionOn(command.ownerId, command.habitId, yesterday) != null,
                )
                val existing = ledger.completionOn(command.ownerId, command.habitId, credit.date.toString())
                val result = existing ?: CheckInRow(
                    command.ownerId, command.recordId, command.habitId, command.occurredAtMillis,
                    credit.date.toString(), credit.zoneId, credit.reason.name, command.value,
                ).also { record ->
                    ledger.insertCheckIn(record)
                    ledger.insertOutbox(OutboxRow(
                        command.ownerId, command.operationId, "checkin.completed", record.id,
                        json.encodeToString(record), command.occurredAtMillis,
                    ))
                }
                ledger.insertReceipt(MutationReceiptRow(command.ownerId, command.operationId, "checkin.completed", request, result.id))
                result
            }
        }
    }
}

internal fun validateIdentity(vararg values: String) {
    require(values.all { it.isNotBlank() && it.length <= 128 && it.none(Char::isISOControl) }) { "Invalid identity" }
}

internal fun HabitRow.definition(): HabitDefinition {
    require(zoneId in ZoneId.getAvailableZoneIds()) { "Invalid IANA timezone" }
    val schedule = when (scheduleKind) {
        "daily" -> { require(scheduleParameter == null); Schedule.Daily }
        "weekdays" -> { require(scheduleParameter == null); Schedule.Weekdays }
        "weekly" -> Schedule.Weekly(requireNotNull(scheduleParameter))
        else -> throw IllegalArgumentException("Unknown schedule")
    }
    val goal = when (goalKind) {
        "completion" -> { require(target == null); Goal.Completion }
        "steps" -> Goal.Numeric(MetricKind.STEPS, requireNotNull(target))
        "duration_minutes" -> Goal.Numeric(MetricKind.DURATION_MINUTES, requireNotNull(target))
        "distance_meters" -> Goal.Numeric(MetricKind.DISTANCE_METERS, requireNotNull(target))
        else -> throw IllegalArgumentException("Unknown goal")
    }
    return HabitDefinition(title, schedule, goal, archived).also { require(it.title == title) { "Title must be normalized" } }
}