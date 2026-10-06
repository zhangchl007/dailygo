package com.dailygo.app

import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AppOverviewTest {
    @Test
    fun startupUsesLocalDateAndNativeDomain() {
        val clock = Clock.fixed(Instant.parse("2026-10-06T17:30:00Z"), ZoneId.of("Asia/Shanghai"))
        val result = AppOverview.empty(clock)
        assertEquals(LocalDate.of(2026, 10, 7), result.date)
        assertEquals(0, result.summary.total)
        assertFalse(result.summary.isCheckedInToday)
    }
}