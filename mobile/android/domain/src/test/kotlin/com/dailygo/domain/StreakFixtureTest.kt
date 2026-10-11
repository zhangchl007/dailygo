package com.dailygo.domain

import java.nio.file.Files
import java.nio.file.Path
import java.time.LocalDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

class StreakFixtureTest {
    @TestFactory
    fun sharedFixtures(): List<DynamicTest> {
        val path = Path.of(System.getProperty("dailygo.fixtures"), "streaks.json")
        val document = Json.parseToJsonElement(Files.readString(path)).jsonObject
        assertEquals(1, document.getValue("schemaVersion").jsonPrimitive.int)
        return document.getValue("cases").jsonArray.map { element ->
            val fixture = element.jsonObject
            DynamicTest.dynamicTest(fixture.getValue("name").jsonPrimitive.content) {
                fun evaluate(): StreakSummary {
                    val schedule = when (fixture.getValue("schedule").jsonPrimitive.content) {
                        "daily" -> Schedule.Daily
                        "weekdays" -> Schedule.Weekdays
                        "weekly" -> Schedule.Weekly(fixture.getValue("target").jsonPrimitive.int)
                        else -> error("Unknown fixture schedule")
                    }
                    val dates = fixture["dates"]?.jsonArray?.map { LocalDate.parse(it.jsonPrimitive.content) }.orEmpty()
                    val expanded = fixture["ranges"]?.jsonArray?.flatMap { range ->
                        val values = range.jsonObject
                        val start = LocalDate.parse(values.getValue("start").jsonPrimitive.content)
                        (0 until values.getValue("days").jsonPrimitive.int).map { start.plusDays(it.toLong()) }
                    }.orEmpty()
                    return StreakCalculator.calculate(schedule, dates + expanded, LocalDate.parse(fixture.getValue("asOf").jsonPrimitive.content))
                }
                if (fixture["error"]?.jsonPrimitive?.boolean == true) {
                    assertThrows(RuntimeException::class.java) { evaluate() }
                } else {
                    val expected: JsonObject = fixture.getValue("expected").jsonObject
                    val result = evaluate()
                    assertEquals(expected.getValue("current").jsonPrimitive.int, result.current)
                    assertEquals(expected.getValue("longest").jsonPrimitive.int, result.longest)
                    assertEquals(expected.getValue("total").jsonPrimitive.int, result.total)
                    assertEquals(expected.getValue("shields").jsonPrimitive.int, result.shields)
                    assertEquals(expected.getValue("today").jsonPrimitive.boolean, result.isCheckedInToday)
                }
            }
        }
    }
}