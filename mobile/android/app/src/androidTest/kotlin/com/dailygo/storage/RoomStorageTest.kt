package com.dailygo.storage

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class RoomStorageTest {
    @Test fun completionAndOutboxSurviveReopen() = runBlocking<Unit> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "storage-test-${UUID.randomUUID()}.db"
        var database = openLocalDatabase(context, name)
        try {
            val habit = HabitRow("guest", "walk", "Walk", "daily", null, "completion", null, "Etc/UTC", 1_791_282_600_000, false)
            val command = CompletionCommand("guest", "complete", "entry", "walk", habit.createdAtMillis, null)
            LocalRepository(database).saveHabit(habit, "create")
            LocalRepository(database).complete(command)
            database.close()
            database = openLocalDatabase(context, name)
            LocalRepository(database).complete(command)
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertEquals(2, database.ledger().outbox("guest").size)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }
}