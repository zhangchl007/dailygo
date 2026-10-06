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
    val version: Int = 1,
    val ownerId: String,
    val habits: List<HabitRow>,
    val checkIns: List<CheckInRow>,
    val progress: List<ProgressRow>,
    val events: List<OutboxRow>,
    val receipts: List<MutationReceiptRow>,
) {
    internal fun validate(expectedOwner: String, json: Json) {
        require(format == "dailygo.android.backup" && version == 1) { "Unsupported backup" }
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
        val definitions = habits.associateBy { it.id }
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
        receipts.forEach { receipt ->
            when (receipt.kind) {
                "habit.created" -> {
                    val request = json.decodeFromString<HabitRow>(receipt.request)
                    request.definition()
                    require(request.ownerId == ownerId && request.id == receipt.resultId && request.id in definitions)
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
                }
                else -> throw IllegalArgumentException("Unsupported receipt kind")
            }
        }
        events.forEach { event ->
            val receipt = requireNotNull(operations[event.eventId]) { "Event has no receipt" }
            require(receipt.kind == event.kind && receipt.resultId == event.entityId)
            val payload = when (event.kind) {
                "habit.created" -> json.encodeToString(json.decodeFromString<HabitRow>(receipt.request))
                "checkin.completed" -> json.encodeToString(checkIns.single { it.id == event.entityId })
                "progress.recorded" -> json.encodeToString(progress.single { it.id == event.entityId })
                else -> throw IllegalArgumentException("Unsupported event kind")
            }
            require(json.parseToJsonElement(event.payload) == json.parseToJsonElement(payload)) { "Invalid event payload" }
        }
    }
}