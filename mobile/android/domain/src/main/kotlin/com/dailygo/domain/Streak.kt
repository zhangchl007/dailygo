package com.dailygo.domain

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

sealed interface Schedule {
    data object Daily : Schedule
    data object Weekdays : Schedule
    data class Weekly(val target: Int) : Schedule {
        init {
            require(target in 1..7) { "Weekly target must be between 1 and 7" }
        }
    }
}

enum class StreakUnit { DAYS, WEEKS }

data class StreakSummary(
    val current: Int,
    val longest: Int,
    val total: Int,
    val shields: Int,
    val isCheckedInToday: Boolean,
    val lastCheckInDate: LocalDate?,
    val unit: StreakUnit,
)

object StreakCalculator {
    fun calculate(
        schedule: Schedule,
        dates: Collection<LocalDate>,
        asOf: LocalDate,
        periodsPerShield: Int = 7,
        maxShields: Int = 3,
    ): StreakSummary {
        require(periodsPerShield > 0 && maxShields >= 0) { "Invalid shield configuration" }
        require(dates.none { it > asOf }) { "Future check-in dates are not allowed" }
        val distinct = dates.toSortedSet()
        val completed = when (schedule) {
            Schedule.Daily -> distinct.toList()
            Schedule.Weekdays -> distinct.filter { it.dayOfWeek.value <= 5 }
            is Schedule.Weekly -> distinct.groupBy { it.weekStart() }
                .filterValues { it.size >= schedule.target }.keys.sorted()
        }
        var current = 0
        var longest = 0
        var shields = 0
        var earningProgress = 0
        var previous: LocalDate? = null

        fun miss(count: Long) {
            if (count <= 0) return
            val used = minOf(count, shields.toLong()).toInt()
            shields -= used
            if (count > used) current = 0
            earningProgress = 0
        }

        for (period in completed) {
            previous?.let { prior -> miss(missingBetween(schedule, prior, period)) }
            current++
            longest = maxOf(longest, current)
            earningProgress++
            if (earningProgress == periodsPerShield) {
                shields = minOf(maxShields, shields + 1)
                earningProgress = 0
            }
            previous = period
        }

        previous?.let { prior ->
            val openPeriod = if (schedule is Schedule.Weekly) asOf.weekStart() else asOf
            miss(missingBetween(schedule, prior, openPeriod))
        }

        return StreakSummary(
            current, longest, distinct.size, shields, asOf in distinct,
            distinct.lastOrNull(), if (schedule is Schedule.Weekly) StreakUnit.WEEKS else StreakUnit.DAYS,
        )
    }

    private fun missingBetween(schedule: Schedule, previous: LocalDate, next: LocalDate): Long {
        if (next <= previous) return 0
        return when (schedule) {
            Schedule.Daily -> ChronoUnit.DAYS.between(previous, next) - 1
            is Schedule.Weekly -> ChronoUnit.WEEKS.between(previous, next) - 1
            Schedule.Weekdays -> {
                val start = previous.plusDays(1)
                val days = ChronoUnit.DAYS.between(start, next)
                val fullWeeks = days / 7
                val remainder = (0 until (days % 7).toInt()).count { offset ->
                    start.plusDays(fullWeeks * 7 + offset).dayOfWeek.value <= 5
                }
                fullWeeks * 5 + remainder
            }
        }.coerceAtLeast(0)
    }

    private fun LocalDate.weekStart(): LocalDate =
        with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
}