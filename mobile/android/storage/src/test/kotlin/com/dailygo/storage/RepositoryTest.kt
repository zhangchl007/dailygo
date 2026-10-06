package com.dailygo.storage

import java.nio.file.Path
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.dailygo.domain.CalendarPolicy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

private inline fun <Result> LocalDatabase.use(block: (LocalDatabase) -> Result): Result {
    try {
        return block(this)
    } finally {
        close()
    }
}

class RepositoryTest {
    @TempDir lateinit var directory: Path
    private val instant = 1791282600000L
    private fun habit(owner: String = "guest") = HabitRow(
        owner, "walk", "Walk", "daily", null, "completion", null, "Asia/Shanghai", instant, false,
    )

    @Test fun `v1 upgrades preserve habits credit pending events and retry receipts`() = runBlocking<Unit> {
        val path = directory.resolve("upgrade.db").toString()
        val original = habit().copy(goalKind = "steps", target = 1000.0)
        val command = CompletionCommand("guest", "complete", "entry", "walk", instant, 1000.0)
        val credit = CalendarPolicy.credit(Instant.ofEpochMilli(instant), original.zoneId)
        val preservedRecord = createVersionOneDatabase(path, Files.readString(
            Path.of("schemas/com.dailygo.storage.LocalDatabase/1.json"),
        ), original, command)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            assertEquals(original, repository.saveHabit(original, "create"))
            val preserved = repository.complete(command)
            assertEquals(preservedRecord, preserved)
            assertEquals(credit.date.toString(), preserved.creditedDate)
            assertEquals(credit.zoneId, preserved.zoneId)
            assertEquals(credit.reason.name, preserved.creditReason)
            assertEquals(instant, preserved.occurredAtMillis)
            assertEquals(2, database.ledger().outbox("guest").size)
            database.ledger().acknowledge("guest", "complete")
            repository.complete(command)
            assertEquals(1, database.ledger().outbox("guest").size)
            repository.recordProgress(ProgressCommand("guest", "progress", "partial", "walk", instant, 400.0))
        }
        openLocalDatabase(path).use { database ->
            assertEquals(original, database.ledger().habit("guest", "walk"))
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertEquals(400.0, database.ledger().progressEntries("guest", "walk").single().value)
            assertEquals(2, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `corrupt database is surfaced unchanged and a restored backup remains readable`() = runBlocking<Unit> {
        val path = directory.resolve("corrupt.db")
        val backup = directory.resolve("backup.db")
        openLocalDatabase(path.toString()).use { LocalRepository(it).saveHabit(habit(), "create") }
        Files.copy(path, backup)
        val corrupt = ByteArray(8192) { 0x42 }
        Files.write(path, corrupt)
        openLocalDatabase(path.toString()).use { database ->
            assertThrows(Exception::class.java) { runBlocking { database.ledger().habits("guest") } }
        }
        assertArrayEquals(corrupt, Files.readAllBytes(path))
        Files.copy(backup, path, StandardCopyOption.REPLACE_EXISTING)
        openLocalDatabase(path.toString()).use { database ->
            assertEquals(habit(), database.ledger().habit("guest", "walk"))
            assertEquals(1, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `sqlite full rolls back progress and permits retry after space is restored`() = runBlocking<Unit> {
        val path = directory.resolve("full.db").toString()
        val command = ProgressCommand("guest", "progress", "entry", "walk", instant, 400.0)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(goalKind = "steps", target = 1000.0), "create")
            constrainOutboxSpace(database)
            val error = assertThrows(Exception::class.java) { runBlocking { repository.recordProgress(command) } }
            assertTrue(generateSequence(error as Throwable?) { it.cause }.any { it.message.orEmpty().contains("full", ignoreCase = true) })
            assertTrue(database.ledger().progressEntries("guest", "walk").isEmpty())
            assertNull(database.ledger().receipt("guest", "progress"))
            assertEquals(1, database.ledger().outbox("guest").size)
            assertEquals(1, database.ledger().habits("guest").size)
            restoreOutboxSpace(database)
            repository.recordProgress(command)
        }
        openLocalDatabase(path).use { database ->
            assertEquals(1, database.ledger().progressEntries("guest", "walk").size)
            assertEquals(2, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `partial progress survives restart without completing a habit or resurrecting events`() = runBlocking<Unit> {
        val path = directory.resolve("progress.db").toString()
        val command = ProgressCommand("guest", "progress", "progress-entry", "walk", instant, 400.0)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(goalKind = "steps", target = 1000.0), "create")
            val result = repository.recordProgress(command)
            assertEquals(result, repository.recordProgress(command))
            assertEquals(400.0, result.value)
            assertEquals("Asia/Shanghai", result.zoneId)
            assertTrue(database.ledger().checkIns("guest", "walk").isEmpty())
            assertTrue(database.ledger().progressEntries("another-owner", "walk").isEmpty())
            database.ledger().acknowledge("guest", "progress")
        }
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            assertEquals(database.ledger().progressEntries("guest", "walk").single(),
                repository.recordProgress(command.copy(asOfMillis = instant + 86_400_000)))
            assertEquals(1, database.ledger().outbox("guest").size)
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.recordProgress(command.copy(value = 500.0)) }
            }
            repository.complete(CompletionCommand("guest", "complete", "completed-entry", "walk", instant, 1000.0))
            assertEquals(1, database.ledger().progressEntries("guest", "walk").size)
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
        }
    }

    @Test fun `progress snapshots do not accumulate and concurrent retries remain owner scoped`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("progress-concurrency.db").toString()).use { database ->
            val repository = LocalRepository(database)
            for (owner in listOf("guest", "another-owner")) {
                repository.saveHabit(habit(owner).copy(goalKind = "steps", target = 1000.0), "create")
            }
            val command = ProgressCommand("guest", "progress", "entry", "walk", instant, 400.0)
            val results = (1..20).map { async(Dispatchers.Default) { repository.recordProgress(command) } }.awaitAll()
            assertEquals(1, results.toSet().size)
            repository.recordProgress(command.copy(ownerId = "another-owner"))
            repository.recordProgress(command.copy(operationId = "more", recordId = "more", value = 600.0))
            repository.recordProgress(command.copy(operationId = "zero", recordId = "zero", value = 0.0))
            assertEquals(setOf(0.0, 400.0, 600.0), database.ledger().progressEntries("guest", "walk").map { it.value }.toSet())
            assertTrue(database.ledger().checkIns("guest", "walk").isEmpty())
            database.ledger().acknowledge("guest", "progress")
            assertEquals(2, database.ledger().outbox("another-owner").size)
            assertEquals(400.0, database.ledger().progressEntries("another-owner", "walk").single().value)
        }
    }

    @Test fun `progress grace credit stays immutable when the habit timezone changes`() = runBlocking<Unit> {
        val path = directory.resolve("progress-timezone.db").toString()
        val ended = Instant.parse("2026-10-06T18:15:00Z").toEpochMilli()
        val started = Instant.parse("2026-10-06T15:45:00Z").toEpochMilli()
        val command = ProgressCommand("guest", "progress", "entry", "walk", ended, 400.0, started)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(goalKind = "steps", target = 1000.0), "create")
            val progress = repository.recordProgress(command)
            assertEquals("2026-10-06", progress.creditedDate)
            assertEquals("MIDNIGHT_GRACE", progress.creditReason)
        }
        val connection = BundledSQLiteDriver().open(path)
        try {
            connection.execSQL("UPDATE habits SET zoneId = 'America/New_York' WHERE ownerId = 'guest' AND id = 'walk'")
        } finally { connection.close() }
        openLocalDatabase(path).use { database ->
            val progress = LocalRepository(database).recordProgress(command.copy(asOfMillis = ended + 86_400_000))
            assertEquals("America/New_York", database.ledger().habit("guest", "walk")!!.zoneId)
            assertEquals("Asia/Shanghai", progress.zoneId)
            assertEquals("2026-10-06", progress.creditedDate)
            assertEquals("MIDNIGHT_GRACE", progress.creditReason)
            assertEquals(ended, progress.occurredAtMillis)
            assertEquals(1, database.ledger().progressEntries("guest", "walk").size)
        }
    }

    @Test fun `partial progress outbox failure rolls back row and retry receipt`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("progress-rollback.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(goalKind = "steps", target = 1000.0), "create")
            database.ledger().insertOutbox(OutboxRow("guest", "progress", "test", "entry", "{}", instant))
            assertThrows(Exception::class.java) {
                runBlocking { repository.recordProgress(ProgressCommand("guest", "progress", "entry", "walk", instant, 400.0)) }
            }
            assertTrue(database.ledger().progressEntries("guest", "walk").isEmpty())
            assertNull(database.ledger().receipt("guest", "progress"))
            assertEquals(2, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `invalid future archived and nonnumeric partial progress leave no mutation`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("invalid-progress.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(goalKind = "steps", target = 1000.0), "create")
            val command = ProgressCommand("guest", "progress", "entry", "walk", instant, 400.0)
            for (value in listOf(-1.0, Double.NaN, Double.POSITIVE_INFINITY, 1000.0, 1001.0)) {
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { repository.recordProgress(command.copy(value = value)) }
                }
            }
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.recordProgress(command.copy(asOfMillis = instant - 1)) }
            }
            repository.saveHabit(habit().copy(id = "archived", goalKind = "steps", target = 1000.0, archived = true), "archive")
            repository.saveHabit(habit().copy(id = "completion"), "completion")
            for (id in listOf("archived", "completion", "missing")) {
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { repository.recordProgress(command.copy(habitId = id)) }
                }
            }
            assertTrue(database.ledger().progressEntries("guest", "walk").isEmpty())
            assertNull(database.ledger().receipt("guest", "progress"))
            assertEquals(3, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `habit and outbox survive reopen`() = runBlocking<Unit> {
        val path = directory.resolve("dailygo.db").toString()
        openLocalDatabase(path).use { database ->
            LocalRepository(database).saveHabit(habit(), "create-walk")
        }
        openLocalDatabase(path).use { database ->
            assertEquals(habit(), database.ledger().habit("guest", "walk"))
            assertEquals(1, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `outbox conflict rolls back habit and receipt`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("rollback.db").toString()).use { database ->
            database.ledger().insertOutbox(OutboxRow("guest", "create-walk", "test", "walk", "{}", instant))
            assertThrows(Exception::class.java) {
                runBlocking { LocalRepository(database).saveHabit(habit(), "create-walk") }
            }
            assertNull(database.ledger().habit("guest", "walk"))
            assertNull(database.ledger().receipt("guest", "create-walk"))
            assertEquals(1, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `completion retry is durable and ownership is isolated`() = runBlocking<Unit> {
        val path = directory.resolve("retry.db").toString()
        val command = CompletionCommand("guest", "complete-walk", "entry", "walk", instant, null)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create-walk")
            assertEquals(repository.complete(command), repository.complete(command))
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertTrue(database.ledger().checkIns("another-owner", "walk").isEmpty())
        }
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.complete(command)
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertEquals(2, database.ledger().outbox("guest").size)
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.complete(command.copy(recordId = "changed")) }
            }
        }
    }

    @Test fun `check-in outbox failure rolls back the completion`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("checkin-rollback.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create-walk")
            database.ledger().insertOutbox(OutboxRow("guest", "complete", "test", "entry", "{}", instant))
            assertThrows(Exception::class.java) {
                runBlocking { repository.complete(CompletionCommand("guest", "complete", "entry", "walk", instant, null)) }
            }
            assertTrue(database.ledger().checkIns("guest", "walk").isEmpty())
            assertNull(database.ledger().receipt("guest", "complete"))
            assertEquals(2, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `acknowledged events do not return when an operation is retried`() = runBlocking<Unit> {
        val path = directory.resolve("acknowledged.db").toString()
        val command = CompletionCommand("guest", "complete", "entry", "walk", instant, null)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create")
            repository.complete(command)
            database.ledger().acknowledge("guest", "create")
            database.ledger().acknowledge("guest", "complete")
        }
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create")
            repository.complete(command.copy(asOfMillis = instant + 86_400_000))
            assertTrue(database.ledger().outbox("guest").isEmpty())
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
        }
    }

    @Test fun `concurrent operations create only one completion per day`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("concurrent.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create")
            val results = (1..20).map { number ->
                async(Dispatchers.Default) {
                    repository.complete(CompletionCommand("guest", "operation-$number", "entry-$number", "walk", instant, null))
                }
            }.awaitAll()
            assertEquals(1, results.map { it.id }.toSet().size)
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertEquals(2, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `owners can use identical entity and operation identifiers independently`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("owners.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create")
            repository.saveHabit(habit("another-owner"), "create")
            repository.complete(CompletionCommand("guest", "complete", "entry", "walk", instant, null))
            assertTrue(database.ledger().checkIns("another-owner", "walk").isEmpty())
            repository.complete(CompletionCommand("another-owner", "complete", "entry", "walk", instant, null))
            database.ledger().acknowledge("guest", "complete")
            assertEquals(2, database.ledger().outbox("another-owner").size)
            assertEquals("another-owner", database.ledger().checkIns("another-owner", "walk").single().ownerId)
        }
    }

    @Test fun `partial invalid future and archived writes leave no mutation`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("invalid.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(goalKind = "steps", target = 1000.0), "create")
            val command = CompletionCommand("guest", "complete", "entry", "walk", instant, 999.0)
            for (invalid in listOf(command, command.copy(value = Double.NaN), command.copy(value = 1000.0, asOfMillis = instant - 1))) {
                assertThrows(IllegalArgumentException::class.java) { runBlocking { repository.complete(invalid) } }
            }
            repository.saveHabit(habit().copy(id = "archived", archived = true), "create-archived")
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.complete(command.copy(habitId = "archived", value = null)) }
            }
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.saveHabit(habit().copy(id = "invalid", target = 0.0), "invalid-create") }
            }
            assertTrue(database.ledger().checkIns("guest", "walk").isEmpty())
            assertNull(database.ledger().receipt("guest", "complete"))
            assertNull(database.ledger().habit("guest", "invalid"))
            assertEquals(2, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `grace credit is stored without recalculation after restart`() = runBlocking<Unit> {
        val path = directory.resolve("grace.db").toString()
        val ended = Instant.parse("2026-10-06T18:15:00Z").toEpochMilli()
        val started = Instant.parse("2026-10-06T15:45:00Z").toEpochMilli()
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create")
            val result = repository.complete(CompletionCommand("guest", "complete", "entry", "walk", ended, null, started))
            assertEquals("2026-10-06", result.creditedDate)
            assertEquals("MIDNIGHT_GRACE", result.creditReason)
        }
        openLocalDatabase(path).use { database ->
            val result = database.ledger().checkIns("guest", "walk").single()
            assertEquals("2026-10-06", result.creditedDate)
            assertEquals("Asia/Shanghai", result.zoneId)
            assertEquals(ended, result.occurredAtMillis)
        }
    }

    @Test fun `unknown schema version fails without deleting existing data`() = runBlocking<Unit> {
        val path = directory.resolve("future-schema.db").toString()
        openLocalDatabase(path).use { LocalRepository(it).saveHabit(habit(), "create") }
        val connection = BundledSQLiteDriver().open(path)
        try {
            connection.execSQL("PRAGMA user_version = 99")
        } finally {
            connection.close()
        }
        openLocalDatabase(path).use { database ->
            val error = assertThrows(Exception::class.java) { runBlocking { database.ledger().habits("guest") } }
            assertTrue(error.message.orEmpty().contains("migration", ignoreCase = true))
        }
        val preserved = BundledSQLiteDriver().open(path)
        try {
            val statement = preserved.prepare("SELECT COUNT(*) FROM habits")
            try {
                assertTrue(statement.step())
                assertEquals(1, statement.getLong(0))
            } finally {
                statement.close()
            }
        } finally {
            preserved.close()
        }
    }
}