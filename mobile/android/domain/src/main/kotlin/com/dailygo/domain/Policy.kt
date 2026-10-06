package com.dailygo.domain

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.floor

enum class MetricKind { STEPS, DURATION_MINUTES, DISTANCE_METERS }

sealed interface Goal {
    data object Completion : Goal
    data class Numeric(val kind: MetricKind, val target: Double) : Goal {
        init {
            require(target.isFinite() && target > 0) { "Target must be finite and positive" }
            require(kind != MetricKind.STEPS || target == floor(target)) { "Step target must be an integer" }
        }
    }

    fun isCompleted(value: Double?): Boolean {
        if (value != null) {
            require(value.isFinite() && value >= 0) { "Value must be finite and nonnegative" }
            require(this !is Numeric || kind != MetricKind.STEPS || value == floor(value)) { "Steps must be an integer" }
        }
        return when (this) {
            Completion -> true
            is Numeric -> value != null && value >= target
        }
    }
}

class HabitDefinition(title: String, val schedule: Schedule, val goal: Goal, val archived: Boolean = false) {
    val title: String = title.trim().also {
        require(it.codePointCount(0, it.length) in 1..100) { "Title must contain 1 to 100 characters" }
        require(it.none(Char::isISOControl)) { "Title must not contain control characters" }
    }

    fun isCompleted(value: Double?): Boolean {
        require(!archived) { "Archived habits cannot accept new check-ins" }
        return goal.isCompleted(value)
    }
}

enum class CreditReason { CURRENT_DAY, MIDNIGHT_GRACE }
data class DateCredit(val date: LocalDate, val zoneId: String, val reason: CreditReason)

object CalendarPolicy {
    fun credit(
        now: Instant, zoneId: String, workoutStartedAt: Instant? = null,
        previousComplete: Boolean = false, graceHours: Int = 3,
    ): DateCredit {
        require(graceHours in 0..23) { "Invalid grace cutoff" }
        require(zoneId in ZoneId.getAvailableZoneIds()) { "A valid IANA timezone is required" }
        require(workoutStartedAt == null || workoutStartedAt <= now) { "Workout start cannot be in the future" }
        val zone = ZoneId.of(zoneId)
        val local = now.atZone(zone)
        val today = local.toLocalDate()
        val previous = today.minusDays(1)
        val overlaps = workoutStartedAt?.atZone(zone)?.toLocalDate() == previous
        return if (local.hour < graceHours && overlaps && !previousComplete) {
            DateCredit(previous, zoneId, CreditReason.MIDNIGHT_GRACE)
        } else {
            DateCredit(today, zoneId, CreditReason.CURRENT_DAY)
        }
    }
}

enum class HealthSource { HEALTH_KIT, HEALTH_CONNECT, MANUAL }
enum class EvidenceStatus { MANUAL, UNAVAILABLE, INSUFFICIENT, HEALTH_BACKED }

data class HealthEvidence(
    val source: HealthSource,
    val startedAt: Instant,
    val endedAt: Instant,
    val steps: Double? = null,
    val durationMinutes: Double? = null,
    val distanceMeters: Double? = null,
) {
    init {
        require(endedAt >= startedAt) { "Invalid health evidence window" }
        require(listOfNotNull(steps, durationMinutes, distanceMeters).all { it.isFinite() && it >= 0 }) { "Invalid measurement" }
        require(steps == null || steps == floor(steps)) { "Steps must be an integer" }
    }
}

object EvidenceEvaluator {
    fun assess(goal: Goal, evidence: HealthEvidence?): EvidenceStatus {
        if (evidence == null) return EvidenceStatus.UNAVAILABLE
        if (evidence.source == HealthSource.MANUAL) return EvidenceStatus.MANUAL
        val measurement = when (goal) {
            Goal.Completion -> listOfNotNull(evidence.steps, evidence.durationMinutes, evidence.distanceMeters).maxOrNull()
            is Goal.Numeric -> when (goal.kind) {
                MetricKind.STEPS -> evidence.steps
                MetricKind.DURATION_MINUTES -> evidence.durationMinutes
                MetricKind.DISTANCE_METERS -> evidence.distanceMeters
            }
        } ?: return EvidenceStatus.UNAVAILABLE
        val meetsGoal = if (goal == Goal.Completion) measurement > 0 else goal.isCompleted(measurement)
        return if (meetsGoal) EvidenceStatus.HEALTH_BACKED else EvidenceStatus.INSUFFICIENT
    }
}