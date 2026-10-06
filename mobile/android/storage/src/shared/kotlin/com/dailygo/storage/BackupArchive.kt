package com.dailygo.storage

import com.dailygo.domain.Goal
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class BackupArchive(
    val format: String = "dailygo.android.backup",
    val version: Int = 4,
    val ownerId: String,
    val habits: List<HabitRow>,
    val checkIns: List<CheckInRow>,
    val progress: List<ProgressRow>,
    val events: List<OutboxRow>,
    val receipts: List<MutationReceiptRow>,
    val deletedHabits: List<DeletedHabitRow> = emptyList(),
    val completionStates: List<CompletionStateRow> = emptyList(),
) {
    internal fun validate(expectedOwner: String, json: Json) {
        require(format == "dailygo.android.backup" && version in 1..4) { "Unsupported backup" }
        require(version != 1 || deletedHabits.isEmpty()) { "Unsupported deletion data" }
        require(version >= 3 || completionStates.isEmpty()) { "Unsupported correction data" }
        validateIdentity(expectedOwner)
        require(ownerId == expectedOwner) { "Backup owner mismatch" }
        fun identities(values: List<Pair<String, String>>) {
            require(values.all { it.first == ownerId }) { "Cross-owner record" }
            values.forEach { validateIdentity(it.first, it.second) }
            require(values.map { it.second }.toSet().size == values.size) { "Duplicate record" }
        }
        identities(habits.map { it.ownerId to it.id })
        identities(checkIns.map { it.ownerId to it.id })
        identities(progress.map { it.ownerId to it.id })
        identities(events.map { it.ownerId to it.eventId })
        identities(receipts.map { it.ownerId to it.operationId })
        identities(deletedHabits.map { it.ownerId to it.habitId })
        identities(completionStates.map { it.ownerId to it.recordId })
        val definitions = habits.associateBy { it.id }
        val deletions = deletedHabits.associateBy { it.habitId }
        require(definitions.keys.intersect(deletions.keys).isEmpty()) { "Deleted habit has data" }
        deletedHabits.forEach { validateIdentity(it.operationId) }
        habits.forEach { it.definition() }
        require(checkIns.map { it.habitId to it.creditedDate }.toSet().size == checkIns.size) { "Duplicate completion date" }
        fun credit(habitId: String, date: String, zone: String, reason: String) {
            require(habitId in definitions) { "Missing habit" }
            require(LocalDate.parse(date).toString() == date && zone in ZoneId.getAvailableZoneIds()) { "Invalid credit" }
            require(reason in setOf("CURRENT_DAY", "MIDNIGHT_GRACE", "LEGACY_IMPORTED")) { "Invalid credit reason" }
        }
        checkIns.forEach {
            credit(it.habitId, it.creditedDate, it.zoneId, it.creditReason)
            require(definitions.getValue(it.habitId).definition().goal.isCompleted(it.value)) { "Incomplete check-in" }
        }
        progress.forEach {
            credit(it.habitId, it.creditedDate, it.zoneId, it.creditReason)
            val goal = definitions.getValue(it.habitId).definition().goal
            require(goal is Goal.Numeric && !goal.isCompleted(it.value)) { "Invalid partial progress" }
        }
        val operations = receipts.associateBy { it.operationId }
        completionStates.forEach { state ->
            val receipt = requireNotNull(operations[state.operationId]) { "Correction has no receipt" }
            val request = json.decodeFromString<CompletionCorrectionCommand>(receipt.request)
            require(receipt.kind == "checkin.corrected" && receipt.resultId == state.recordId)
            require(request.ownerId == state.ownerId && request.recordId == state.recordId && request.operationId == state.operationId &&
                request.active == state.active && request.occurredAtMillis == state.occurredAtMillis)
        }
        deletedHabits.forEach { deletion ->
            val receipt = requireNotNull(operations[deletion.operationId]) { "Deletion has no receipt" }
            require(receipt.kind == "habit.deleted" && receipt.resultId == deletion.habitId) { "Invalid deletion receipt" }
        }
        receipts.forEach { receipt ->
            when (receipt.kind) {
                "checkin.corrected" -> {
                    val request = json.decodeFromString<CompletionCorrectionCommand>(receipt.request)
                    val entry = requireNotNull(checkIns.singleOrNull { it.id == request.recordId })
                    validateIdentity(request.ownerId, request.operationId, request.recordId)
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && request.recordId == receipt.resultId)
                    require(request.asOfMillis == request.occurredAtMillis && request.occurredAtMillis >= entry.occurredAtMillis)
                    require(completionStates.any { it.recordId == request.recordId && it.occurredAtMillis >= request.occurredAtMillis })
                }
                "habit.retired" -> {
                    val request = json.decodeFromString<RetiredHabitOperation>(receipt.request)
                    validateIdentity(request.ownerId, request.operationId, request.habitId)
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && request.habitId == receipt.resultId && request.habitId in deletions)
                }
                "habit.deleted" -> {
                    val request = json.decodeFromString<HabitDeleteCommand>(receipt.request)
                    val deletion = requireNotNull(deletions[receipt.resultId]) { "Missing deletion fence" }
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && request.habitId == receipt.resultId)
                    require(request.asOfMillis == request.occurredAtMillis && request.operationId == deletion.operationId && request.occurredAtMillis == deletion.occurredAtMillis)
                }
                "habit.created" -> {
                    val request = json.decodeFromString<HabitRow>(receipt.request)
                    request.definition()
                    require(request.ownerId == ownerId && request.id == receipt.resultId && request.id in definitions)
                }
                "habit.edited" -> {
                    val request = json.decodeFromString<HabitEditCommand>(receipt.request)
                    val habit = requireNotNull(definitions[request.habitId]) { "Missing habit" }
                    validateIdentity(request.ownerId, request.operationId, request.habitId)
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && request.habitId == receipt.resultId)
                    require(request.asOfMillis == request.occurredAtMillis && request.occurredAtMillis >= habit.createdAtMillis)
                    habit.copy(title = request.title, scheduleKind = request.scheduleKind,
                        scheduleParameter = request.scheduleParameter, zoneId = request.zoneId).definition()
                }
                "habit.goal_changed" -> {
                    require(version >= 4) { "Unsupported goal change data" }
                    val request = json.decodeFromString<HabitGoalCommand>(receipt.request)
                    val habit = requireNotNull(definitions[request.habitId]) { "Missing habit" }
                    validateIdentity(request.ownerId, request.operationId, request.habitId)
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && request.habitId == receipt.resultId)
                    require(request.asOfMillis == request.occurredAtMillis && request.occurredAtMillis >= habit.createdAtMillis)
                    habit.copy(goalKind = request.goalKind, target = request.target).definition()
                }
                "habit.archived", "habit.restored" -> {
                    val request = json.decodeFromString<HabitArchiveCommand>(receipt.request)
                    val habit = requireNotNull(definitions[request.habitId]) { "Missing habit" }
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && request.habitId == receipt.resultId)
                    require(request.archived == (receipt.kind == "habit.archived"))
                    require(request.asOfMillis == request.occurredAtMillis && request.occurredAtMillis >= habit.createdAtMillis)
                }
                "checkin.completed" -> {
                    val request = json.decodeFromString<CompletionCommand>(receipt.request)
                    val result = checkIns.singleOrNull { it.id == receipt.resultId }
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && result != null && result.habitId == request.habitId)
                    require(request.occurredAtMillis <= request.asOfMillis)
                    require(request.workoutStartedAtMillis == null || request.workoutStartedAtMillis <= request.occurredAtMillis)
                    validateIdentity(request.recordId, request.habitId)
                    require(definitions.getValue(request.habitId).definition().goal.isCompleted(request.value))
                }
                "progress.recorded" -> {
                    val request = json.decodeFromString<ProgressCommand>(receipt.request)
                    val result = progress.singleOrNull { it.id == receipt.resultId }
                    require(request.ownerId == ownerId && request.operationId == receipt.operationId && result != null && result.habitId == request.habitId)
                    require(request.occurredAtMillis <= request.asOfMillis && result.value == request.value && result.id == request.recordId)
                    require(request.workoutStartedAtMillis == null || request.workoutStartedAtMillis <= request.occurredAtMillis)
                    require(result.occurredAtMillis == request.occurredAtMillis)
                    validateIdentity(request.recordId, request.habitId)
                    request.correctsRecordId?.let { recordId ->
                        require(version >= 4 && request.workoutStartedAtMillis == null) { "Unsupported correction data" }
                        validateIdentity(recordId)
                        val original = requireNotNull(progress.singleOrNull { it.id == recordId }) { "Missing original progress" }
                        require(result.id != original.id && original.habitId == result.habitId && result.occurredAtMillis >= original.occurredAtMillis)
                        require(result.creditedDate == original.creditedDate && result.zoneId == original.zoneId && result.creditReason == original.creditReason)
                    }
                }
                else -> throw IllegalArgumentException("Unsupported receipt kind")
            }
        }
        events.forEach { event ->
            val receipt = requireNotNull(operations[event.eventId]) { "Event has no receipt" }
            require(receipt.kind == event.kind && receipt.resultId == event.entityId)
            require(event.kind != "habit.retired") { "Retired operation has an event" }
            val payload = when (event.kind) {
                "checkin.corrected" -> {
                    val request = json.decodeFromString<CompletionCorrectionCommand>(receipt.request)
                    require(event.createdAtMillis == request.occurredAtMillis)
                    json.encodeToString(request)
                }
                "habit.created" -> json.encodeToString(json.decodeFromString<HabitRow>(receipt.request))
                "habit.deleted" -> {
                    val request = json.decodeFromString<HabitDeleteCommand>(receipt.request)
                    require(event.createdAtMillis == request.occurredAtMillis) { "Invalid event timestamp" }
                    json.encodeToString(request)
                }
                "habit.edited" -> {
                    val request = json.decodeFromString<HabitEditCommand>(receipt.request)
                    require(event.createdAtMillis == request.occurredAtMillis) { "Invalid event timestamp" }
                    json.encodeToString(request)
                }
                "habit.goal_changed" -> {
                    val request = json.decodeFromString<HabitGoalCommand>(receipt.request)
                    require(event.createdAtMillis == request.occurredAtMillis) { "Invalid event timestamp" }
                    json.encodeToString(request)
                }
                "habit.archived", "habit.restored" -> {
                    val request = json.decodeFromString<HabitArchiveCommand>(receipt.request)
                    require(event.createdAtMillis == request.occurredAtMillis) { "Invalid event timestamp" }
                    json.encodeToString(request)
                }
                "checkin.completed" -> json.encodeToString(checkIns.single { it.id == event.entityId })
                "progress.recorded" -> json.encodeToString(progress.single { it.id == event.entityId })
                else -> throw IllegalArgumentException("Unsupported event kind")
            }
            require(json.parseToJsonElement(event.payload) == json.parseToJsonElement(payload)) { "Invalid event payload" }
        }
    }
}