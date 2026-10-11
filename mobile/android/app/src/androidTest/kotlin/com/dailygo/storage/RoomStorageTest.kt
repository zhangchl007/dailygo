package com.dailygo.storage

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

class RoomStorageTest {
    @Test fun legacyBackupAndDeletionRemainAtomicAndOwnerScopedAcrossReopen() = runBlocking<Unit> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val name = "transfer-test-${UUID.randomUUID()}.db"
        val restoredName = "restore-test-${UUID.randomUUID()}.db"
        val source = java.io.File(context.cacheDir, "legacy-${UUID.randomUUID()}.db")
        var database = openLocalDatabase(context, name)
        try {
            val fixture = Json.parseToJsonElement(instrumentation.context.assets.open("v1.json").bufferedReader().use { it.readText() }).jsonObject
            val connection = BundledSQLiteDriver().open(source.absolutePath)
            try { fixture.getValue("statements").jsonArray.forEach { connection.execSQL(it.jsonPrimitive.content) } }
            finally { connection.close() }
            val bytes = source.readBytes()
            val repository = LocalRepository(database)
            assertTrue(!repository.importLegacy(source.absolutePath, "guest", emptyMap(), false).imported)
            assertTrue(database.ledger().habits("guest").isEmpty())
            assertTrue(repository.importLegacy(source.absolutePath, "guest", mapOf("walk" to "Asia/Shanghai"), true).imported)
            database.ledger().acknowledge("guest", "legacy-complete")
            assertTrue(repository.importLegacy(source.absolutePath, "guest", mapOf("walk" to "Asia/Shanghai"), true).imported)
            assertEquals(1, database.ledger().outbox("guest").size)
            assertArrayEquals(bytes, source.readBytes())
            val backup = repository.exportOwner("guest")
            val restored = openLocalDatabase(context, restoredName)
            try {
                LocalRepository(restored).importOwner("guest", backup)
                LocalRepository(restored).importOwner("guest", backup)
                assertEquals(backup, LocalRepository(restored).exportOwner("guest"))
                assertEquals("done", restored.ledger().checkIns("guest", "walk").single().id)
            } finally { restored.close() }
            repository.saveHabit(HabitRow("other", "walk", "Walk", "daily", null, "completion", null, "Etc/UTC", 1_791_282_600_000, false), "create")
            repository.deleteOwner("guest")
            database.close()
            database = openLocalDatabase(context, name)
            assertThrows(IllegalArgumentException::class.java) { runBlocking { LocalRepository(database).importOwner("guest", backup) } }
            assertTrue(database.ledger().habits("guest").isEmpty())
            assertTrue(database.ledger().outbox("guest").isEmpty())
            assertEquals(1, database.ledger().habits("other").size)
        } finally {
            database.close()
            context.deleteDatabase(name)
            context.deleteDatabase(restoredName)
            source.delete()
        }
    }

    @Test fun fullDatabaseRollsBackAndCanRetryAfterSpaceIsRestored() = runBlocking<Unit> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "full-test-${UUID.randomUUID()}.db"
        var database = openLocalDatabase(context, name)
        try {
            val habit = HabitRow("guest", "walk", "Walk", "daily", null, "steps", 1000.0, "Etc/UTC", 1_791_282_600_000, false)
            val command = ProgressCommand("guest", "progress", "partial", "walk", habit.createdAtMillis, 400.0)
            LocalRepository(database).saveHabit(habit, "create")
            constrainOutboxSpace(database)
            val error = assertThrows(Exception::class.java) {
                runBlocking { LocalRepository(database).recordProgress(command) }
            }
            assertTrue(generateSequence(error as Throwable?) { it.cause }.any { it.message.orEmpty().contains("full", ignoreCase = true) })
            assertTrue(database.ledger().progressEntries("guest", "walk").isEmpty())
            assertNull(database.ledger().receipt("guest", "progress"))
            assertEquals(1, database.ledger().outbox("guest").size)
            restoreOutboxSpace(database)
            LocalRepository(database).recordProgress(command)
            database.close()
            database = openLocalDatabase(context, name)
            assertEquals(1, database.ledger().progressEntries("guest", "walk").size)
            assertEquals(2, database.ledger().outbox("guest").size)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun corruptionDoesNotReplaceTheDatabaseAndBackupCanBeRestored() = runBlocking<Unit> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "corruption-test-${UUID.randomUUID()}.db"
        val file = context.getDatabasePath(name)
        var database = openLocalDatabase(context, name)
        try {
            val habit = HabitRow("guest", "walk", "Walk", "daily", null, "completion", null, "Etc/UTC", 1_791_282_600_000, false)
            LocalRepository(database).saveHabit(habit, "create")
            database.close()
            val backup = file.readBytes()
            val corrupt = ByteArray(8192) { 0x42 }
            file.writeBytes(corrupt)
            database = openLocalDatabase(context, name)
            assertThrows(Exception::class.java) { runBlocking { database.ledger().habits("guest") } }
            database.close()
            assertArrayEquals(corrupt, file.readBytes())
            file.writeBytes(backup)
            database = openLocalDatabase(context, name)
            assertEquals(habit, database.ledger().habit("guest", "walk"))
            assertEquals(1, database.ledger().outbox("guest").size)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun partialProgressSurvivesReopenAndAcknowledgedRetry() = runBlocking<Unit> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "progress-test-${UUID.randomUUID()}.db"
        var database = openLocalDatabase(context, name)
        try {
            val habit = HabitRow("guest", "walk", "Walk", "daily", null, "steps", 1000.0, "Etc/UTC", 1_791_282_600_000, false)
            val command = ProgressCommand("guest", "progress", "partial", "walk", habit.createdAtMillis, 400.0)
            LocalRepository(database).saveHabit(habit, "create")
            val original = LocalRepository(database).recordProgress(command)
            database.ledger().acknowledge("guest", "progress")
            database.close()
            database = openLocalDatabase(context, name)
            assertEquals(original, LocalRepository(database).recordProgress(command))
            assertEquals(1, database.ledger().progressEntries("guest", "walk").size)
            assertTrue(database.ledger().checkIns("guest", "walk").isEmpty())
            assertTrue(database.ledger().progressEntries("another-owner", "walk").isEmpty())
            assertEquals(1, database.ledger().outbox("guest").size)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun progressOutboxFailureRollsBack() = runBlocking<Unit> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "rollback-test-${UUID.randomUUID()}.db"
        val database = openLocalDatabase(context, name)
        try {
            val habit = HabitRow("guest", "walk", "Walk", "daily", null, "steps", 1000.0, "Etc/UTC", 1_791_282_600_000, false)
            LocalRepository(database).saveHabit(habit, "create")
            database.ledger().insertOutbox(OutboxRow("guest", "progress", "test", "partial", "{}", habit.createdAtMillis))
            assertThrows(Exception::class.java) {
                runBlocking { LocalRepository(database).recordProgress(ProgressCommand("guest", "progress", "partial", "walk", habit.createdAtMillis, 400.0)) }
            }
            assertTrue(database.ledger().progressEntries("guest", "walk").isEmpty())
            assertNull(database.ledger().receipt("guest", "progress"))
            assertEquals(2, database.ledger().outbox("guest").size)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    @Test fun versionOneMigratesWithoutLosingPendingEventsOrRetryReceipts() = runBlocking<Unit> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val name = "migration-test-${UUID.randomUUID()}.db"
        val file = context.getDatabasePath(name)
        val directory = requireNotNull(file.parentFile)
        check(directory.isDirectory || directory.mkdirs())
        val schema = instrumentation.context.assets.open("com.dailygo.storage.LocalDatabase/1.json")
            .bufferedReader().use { it.readText() }
        val habit = HabitRow("guest", "walk", "Walk", "daily", null, "steps", 1000.0, "Etc/UTC", 1_791_282_600_000, false)
        val command = CompletionCommand("guest", "complete", "entry", "walk", habit.createdAtMillis, 1000.0)
        val preserved = createPriorDatabase(file.absolutePath, schema, habit, command)
        var database = openLocalDatabase(context, name)
        try {
            assertEquals(habit, LocalRepository(database).saveHabit(habit, "create"))
            assertEquals(preserved, LocalRepository(database).complete(command))
            assertEquals(2, database.ledger().outbox("guest").size)
            database.ledger().acknowledge("guest", "complete")
            LocalRepository(database).complete(command)
            assertEquals(1, database.ledger().outbox("guest").size)
            LocalRepository(database).recordProgress(ProgressCommand("guest", "progress", "partial", "walk", habit.createdAtMillis, 400.0))
            database.close()
            database = openLocalDatabase(context, name)
            assertEquals(preserved, database.ledger().checkIns("guest", "walk").single())
            assertEquals(400.0, database.ledger().progressEntries("guest", "walk").single().value, 0.0)
            assertEquals(2, database.ledger().outbox("guest").size)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

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