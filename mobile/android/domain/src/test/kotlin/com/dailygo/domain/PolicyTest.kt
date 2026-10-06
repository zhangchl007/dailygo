package com.dailygo.domain

import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class PolicyTest {
    @TestFactory
    fun calendarFixtures(): List<DynamicTest> {
        val path = Path.of(System.getProperty("dailygo.fixtures"), "calendar.json")
        val document = Json.parseToJsonElement(Files.readString(path)).jsonObject
        assertEquals(1, document.getValue("schemaVersion").jsonPrimitive.int)
        return document.getValue("cases").jsonArray.map { element ->
            val fixture = element.jsonObject
            DynamicTest.dynamicTest(fixture.getValue("name").jsonPrimitive.content) {
                fun evaluate() = CalendarPolicy.credit(
                    now = Instant.parse(fixture.getValue("now").jsonPrimitive.content),
                    zoneId = fixture.getValue("zone").jsonPrimitive.content,
                    workoutStartedAt = fixture["started"]?.jsonPrimitive?.content?.let(Instant::parse),
                    previousComplete = fixture["previousComplete"]?.jsonPrimitive?.boolean ?: false,
                    graceHours = fixture["graceHours"]?.jsonPrimitive?.int ?: 3,
                ).date.toString()
                if (fixture["error"]?.jsonPrimitive?.boolean == true) {
                    assertThrows(RuntimeException::class.java) { evaluate() }
                } else {
                    assertEquals(fixture.getValue("expected").jsonPrimitive.content, evaluate())
                }
            }
        }
    }

    @Test
    fun titleAndTargetValidation() {
        assertEquals("Morning walk", HabitDefinition("  Morning walk  ", Schedule.Daily, Goal.Completion).title)
        for (title in listOf("", "  ", "x".repeat(101), "😀".repeat(101))) {
            assertThrows(IllegalArgumentException::class.java) { HabitDefinition(title, Schedule.Daily, Goal.Completion) }
        }
        assertEquals("😀".repeat(100), HabitDefinition("😀".repeat(100), Schedule.Daily, Goal.Completion).title)
        for (target in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY, 1.5)) {
            assertThrows(IllegalArgumentException::class.java) { Goal.Numeric(MetricKind.STEPS, target) }
        }
    }

    @Test
    fun completionRequiresActualGoalAndActiveHabit() {
        val goal = Goal.Numeric(MetricKind.DISTANCE_METERS, 5000.0)
        assertFalse(goal.isCompleted(null))
        assertFalse(goal.isCompleted(4999.0))
        assertTrue(goal.isCompleted(5000.0))
        assertTrue(Goal.Completion.isCompleted(null))
        for (value in listOf(-1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertThrows(IllegalArgumentException::class.java) { goal.isCompleted(value) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            HabitDefinition("Archived", Schedule.Daily, goal, archived = true).isCompleted(6000.0)
        }
    }

    @Test
    fun evidenceIsSourceBackedAndMissingIsUnknown() {
        val goal = Goal.Numeric(MetricKind.STEPS, 5000.0)
        val start = Instant.parse("2026-10-06T10:00:00Z")
        val end = Instant.parse("2026-10-06T11:00:00Z")
        assertEquals(EvidenceStatus.UNAVAILABLE, EvidenceEvaluator.assess(goal, null))
        assertEquals(EvidenceStatus.MANUAL, EvidenceEvaluator.assess(goal, HealthEvidence(HealthSource.MANUAL, start, end, steps = 6000.0)))
        assertEquals(EvidenceStatus.UNAVAILABLE, EvidenceEvaluator.assess(goal, HealthEvidence(HealthSource.HEALTH_CONNECT, start, end)))
        assertEquals(EvidenceStatus.INSUFFICIENT, EvidenceEvaluator.assess(goal, HealthEvidence(HealthSource.HEALTH_CONNECT, start, end, steps = 3500.0)))
        assertEquals(EvidenceStatus.HEALTH_BACKED, EvidenceEvaluator.assess(goal, HealthEvidence(HealthSource.HEALTH_CONNECT, start, end, steps = 5000.0)))
        assertThrows(IllegalArgumentException::class.java) { HealthEvidence(HealthSource.HEALTH_CONNECT, start, end, steps = Double.NaN) }
        assertThrows(IllegalArgumentException::class.java) { HealthEvidence(HealthSource.HEALTH_CONNECT, end, start) }
    }
}