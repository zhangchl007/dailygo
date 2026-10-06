package com.dailygo.app

import com.dailygo.domain.CalendarPolicy
import com.dailygo.domain.Schedule
import com.dailygo.domain.StreakCalculator
import com.dailygo.domain.StreakSummary
import java.time.Clock
import java.time.LocalDate

data class AppOverview(val date: LocalDate, val summary: StreakSummary) {
    companion object {
        fun empty(clock: Clock): AppOverview {
            val credit = CalendarPolicy.credit(clock.instant(), clock.zone.id)
            return AppOverview(credit.date, StreakCalculator.calculate(Schedule.Daily, emptyList(), credit.date))
        }
    }
}