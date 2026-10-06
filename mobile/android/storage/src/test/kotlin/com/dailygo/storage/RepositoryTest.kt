package com.dailygo.storage

import java.nio.file.Path
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import androidx.room.immediateTransaction
import androidx.room.useWriterConnection
import com.dailygo.domain.CalendarPolicy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

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

    @Test fun `archival preserves history and retries cannot undo restoration`() = runBlocking<Unit> {
        val path = directory.resolve("archival.db").toString()
        val archive = HabitArchiveCommand("guest", "archive", "walk", true, instant + 1)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create")
            repository.saveHabit(habit("other"), "create")
            repository.complete(CompletionCommand("guest", "complete", "done", "walk", instant, null))
            assertTrue(repository.setHabitArchived(archive).archived)
            assertFalse(database.ledger().habit("other", "walk")!!.archived)
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.complete(CompletionCommand("guest", "blocked", "blocked", "walk", instant + 2, null)) }
            }
            repository.exportOwner("guest")
        }
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            assertTrue(repository.setHabitArchived(archive).archived)
            database.ledger().acknowledge("guest", "archive")
            assertFalse(repository.setHabitArchived(archive.copy(operationId = "restore", archived = false, occurredAtMillis = instant + 2, asOfMillis = instant + 2)).archived)
            assertFalse(repository.setHabitArchived(archive.copy(asOfMillis = instant + 10)).archived)
            assertFalse(database.ledger().outbox("guest").any { it.eventId == "archive" })
            val backup = repository.exportOwner("guest")
            openLocalDatabase(directory.resolve("archival-restored.db").toString()).use { restored ->
                val restoredRepository = LocalRepository(restored)
                restoredRepository.importOwner("guest", backup)
                assertFalse(restoredRepository.setHabitArchived(archive).archived)
                assertEquals(1, restored.ledger().checkIns("guest", "walk").size)
            }
        }
    }

    @Test fun `archival failures are atomic and enforce ownership timestamps and deletion fences`() = runBlocking<Unit> {
        openLocalDatabase(directory.resolve("archival-failure.db").toString()).use { database ->
            val repository = LocalRepository(database)
            val original = habit().copy(goalKind = "steps", target = 1000.0)
            val archive = HabitArchiveCommand("guest", "archive", "walk", true, instant + 1)
            repository.saveHabit(original, "create")
            repository.recordProgress(ProgressCommand("guest", "progress", "partial", "walk", instant, 400.0))
            database.ledger().insertOutbox(OutboxRow("guest", "archive", "conflict", "walk", "{}", instant))
            assertThrows(Exception::class.java) { runBlocking { repository.setHabitArchived(archive) } }
            assertEquals(original, database.ledger().habit("guest", "walk"))
            assertNull(database.ledger().receipt("guest", "archive"))
            database.ledger().acknowledge("guest", "archive")
            for (invalid in listOf(
                archive.copy(ownerId = "missing-owner"),
                archive.copy(occurredAtMillis = instant + 2, asOfMillis = instant + 1),
                archive.copy(occurredAtMillis = instant - 1, asOfMillis = instant - 1),
            )) {
                assertThrows(IllegalArgumentException::class.java) { runBlocking { repository.setHabitArchived(invalid) } }
            }
            assertEquals(original, database.ledger().habit("guest", "walk"))
            repository.setHabitArchived(archive)
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.setHabitArchived(archive.copy(archived = false)) }
            }
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.recordProgress(ProgressCommand("guest", "blocked", "blocked", "walk", instant + 2, 200.0)) }
            }
            assertEquals(400.0, database.ledger().progressEntries("guest", "walk").single().value)
            val json = Json { encodeDefaults = true }
            val backup = json.decodeFromString<BackupArchive>(repository.exportOwner("guest"))
            val corrupted = backup.copy(events = backup.events.map { if (it.eventId == "archive") it.copy(createdAtMillis = instant + 2) else it })
            openLocalDatabase(directory.resolve("archival-invalid.db").toString()).use { target ->
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { LocalRepository(target).importOwner("guest", json.encodeToString(BackupArchive.serializer(), corrupted)) }
                }
                assertTrue(target.ledger().habits("guest").isEmpty())
            }
            repository.deleteOwner("guest")
            assertThrows(IllegalArgumentException::class.java) { runBlocking { repository.setHabitArchived(archive) } }
        }
    }

    @Test fun `owner deletion survives reopen and fences old retries without affecting another owner`() = runBlocking<Unit> {
        val path = directory.resolve("delete-owner.db").toString()
        val original = habit().copy(goalKind = "steps", target = 1000.0)
        val command = ProgressCommand("guest", "progress", "entry", "walk", instant, 400.0)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(original, "create")
            repository.saveHabit(original.copy(ownerId = "other"), "create")
            repository.recordProgress(command)
            repository.complete(CompletionCommand("guest", "complete", "done", "walk", instant, 1000.0))
            repository.deleteOwner("guest")
            repository.deleteOwner("guest")
            assertTrue(database.ledger().habits("guest").isEmpty())
            assertTrue(database.ledger().checkIns("guest", "walk").isEmpty())
            assertTrue(database.ledger().progressEntries("guest", "walk").isEmpty())
            assertTrue(database.ledger().outbox("guest").isEmpty())
            assertNull(database.ledger().receipt("guest", "create"))
            assertEquals(1, database.ledger().habits("other").size)
            assertEquals(1, database.ledger().outbox("other").size)
        }
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            assertThrows(IllegalArgumentException::class.java) { runBlocking { repository.saveHabit(original, "create") } }
            assertThrows(IllegalArgumentException::class.java) { runBlocking { repository.recordProgress(command) } }
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.complete(CompletionCommand("guest", "complete", "done", "walk", instant, 1000.0)) }
            }
            assertTrue(database.ledger().habits("guest").isEmpty())
        }
    }

    @Test fun `versioned backup restores records pending events and acknowledged retry state`() = runBlocking<Unit> {
        val source = directory.resolve("export.db").toString()
        val target = directory.resolve("import.db").toString()
        val original = habit().copy(goalKind = "steps", target = 1000.0)
        val command = ProgressCommand("guest", "progress", "entry", "walk", instant, 400.0)
        val backup = openLocalDatabase(source).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(original, "create")
            repository.saveHabit(habit("other"), "create")
            repository.recordProgress(command)
            repository.complete(CompletionCommand("guest", "complete", "done", "walk", instant, 1000.0))
            database.ledger().acknowledge("guest", "progress")
            database.useWriterConnection { connection ->
                connection.usePrepared("UPDATE habits SET zoneId = 'America/New_York' WHERE ownerId = 'guest' AND id = 'walk'") { it.step() }
            }
            repository.exportOwner("guest")
        }
        openLocalDatabase(target).use { database ->
            val repository = LocalRepository(database)
            repository.importOwner("guest", backup)
            repository.importOwner("guest", backup)
            assertEquals(original.copy(zoneId = "America/New_York"), database.ledger().habit("guest", "walk"))
            assertEquals(1, database.ledger().progressEntries("guest", "walk").size)
            assertEquals("Asia/Shanghai", database.ledger().progressEntries("guest", "walk").single().zoneId)
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertEquals(2, database.ledger().outbox("guest").size)
            assertTrue(database.ledger().habits("other").isEmpty())
            repository.recordProgress(command.copy(asOfMillis = instant + 1000))
            assertEquals(2, database.ledger().outbox("guest").size)
            assertEquals(backup, repository.exportOwner("guest"))
            repository.deleteOwner("guest")
            assertThrows(IllegalArgumentException::class.java) { runBlocking { repository.importOwner("guest", backup) } }
        }
    }

    @Test fun `backup rejects malformed versions ownership duplicates and conflicts atomically`() = runBlocking<Unit> {
        val backup = openLocalDatabase(directory.resolve("backup-source.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(id = "first"), "first")
            repository.saveHabit(habit(), "create")
            repository.exportOwner("guest")
        }
        openLocalDatabase(directory.resolve("backup-target.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit().copy(title = "Existing"), "existing")
            for (invalid in listOf("{", backup.replace("\"version\":1", "\"version\":99"),
                backup.replace("\"ownerId\":\"guest\"", "\"ownerId\":\"other\""), backup)) {
                assertThrows(Exception::class.java) { runBlocking { repository.importOwner("guest", invalid) } }
                assertEquals(listOf("Existing"), database.ledger().habits("guest").map { it.title })
                assertEquals(1, database.ledger().outbox("guest").size)
                assertNull(database.ledger().receipt("guest", "first"))
            }
            database.useWriterConnection { connection ->
                connection.immediateTransaction {
                    connection.usePrepared("CREATE TRIGGER fail_delete BEFORE DELETE ON mutation_receipts BEGIN SELECT RAISE(ABORT, 'delete failure'); END") { it.step() }
                }
            }
            assertThrows(Exception::class.java) { runBlocking { repository.deleteOwner("guest") } }
            assertFalse(database.ledger().isDeleted("guest"))
            assertEquals(1, database.ledger().habits("guest").size)
            assertEquals(1, database.ledger().outbox("guest").size)
        }
    }

    @Test fun `legacy import requires explicit resolutions preserves pending changes and never alters source`() = runBlocking<Unit> {
        val source = directory.resolve("legacy.db")
        val fixture = Json.parseToJsonElement(Files.readString(Path.of("../../../tests/fixtures/legacy/v1.json"))).jsonObject
        val connection = BundledSQLiteDriver().open(source.toString())
        try { fixture.getValue("statements").jsonArray.forEach { connection.execSQL(it.jsonPrimitive.content) } }
        finally { connection.close() }
        val originalBytes = Files.readAllBytes(source)
        openLocalDatabase(directory.resolve("legacy-target.db").toString()).use { database ->
            val repository = LocalRepository(database)
            val unresolved = repository.importLegacy(source.toString(), "guest", emptyMap(), false)
            assertFalse(unresolved.imported)
            assertTrue(unresolved.issues.isNotEmpty())
            assertTrue(database.ledger().habits("guest").isEmpty())
            assertNotNull(LegacyImport.read(source.toString(), "guest", mapOf("walk" to "Asia/Shanghai"), true).archive)
            val resolved = repository.importLegacy(source.toString(), "guest", mapOf("walk" to "Asia/Shanghai"), true)
            assertTrue(resolved.imported)
            assertTrue(resolved.issues.any { it.code == "UNVERIFIED_PROVENANCE" })
            assertEquals(instant, database.ledger().checkIn("guest", "done")!!.occurredAtMillis)
            assertEquals("2026-10-06", database.ledger().checkIn("guest", "done")!!.creditedDate)
            assertEquals("LEGACY_IMPORTED", database.ledger().checkIn("guest", "done")!!.creditReason)
            assertEquals(setOf("legacy-create", "legacy-complete"), database.ledger().outbox("guest").map { it.eventId }.toSet())
            database.ledger().acknowledge("guest", "legacy-complete")
            assertTrue(repository.importLegacy(source.toString(), "guest", mapOf("walk" to "Asia/Shanghai"), true).imported)
            assertEquals(1, database.ledger().outbox("guest").size)
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            val archive = repository.exportOwner("guest")
            assertTrue(archive.contains("LEGACY_IMPORTED"))
        }
        assertArrayEquals(originalBytes, Files.readAllBytes(source))
        assertFalse(Files.exists(Path.of(source.toString() + "-wal")))
    }

    @Test fun `fractional step progress and malformed legacy sources leave no target mutation`() = runBlocking<Unit> {
        val source = directory.resolve("invalid-legacy.db")
        val fixture = Json.parseToJsonElement(Files.readString(Path.of("../../../tests/fixtures/legacy/v1.json"))).jsonObject
        val connection = BundledSQLiteDriver().open(source.toString())
        try {
            fixture.getValue("statements").jsonArray.forEach { connection.execSQL(it.jsonPrimitive.content) }
            connection.execSQL("UPDATE check_in_records SET local_date = 'not-a-date'")
        } finally { connection.close() }
        val bytes = Files.readAllBytes(source)
        openLocalDatabase(directory.resolve("invalid-target.db").toString()).use { database ->
            val repository = LocalRepository(database)
            assertFalse(repository.importLegacy(source.toString(), "guest", mapOf("walk" to "Asia/Shanghai"), true).imported)
            assertTrue(database.ledger().habits("guest").isEmpty())
            repository.saveHabit(habit().copy(goalKind = "steps", target = 1000.0), "create")
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.recordProgress(ProgressCommand("guest", "partial", "entry", "walk", instant, 0.5)) }
            }
            assertTrue(database.ledger().progressEntries("guest", "walk").isEmpty())
            assertEquals(1, database.ledger().outbox("guest").size)
        }
        assertArrayEquals(bytes, Files.readAllBytes(source))
    }

    @Test fun `backup disk-full rollback leaves no imported records and can recover`() = runBlocking<Unit> {
        val backup = openLocalDatabase(directory.resolve("full-import-source.db").toString()).use { database ->
            val repository = LocalRepository(database)
            repository.saveHabit(habit(), "create")
            repository.exportOwner("guest")
        }
        openLocalDatabase(directory.resolve("full-import-target.db").toString()).use { database ->
            val repository = LocalRepository(database)
            constrainOutboxSpace(database)
            assertThrows(Exception::class.java) { runBlocking { repository.importOwner("guest", backup) } }
            assertTrue(database.ledger().habits("guest").isEmpty())
            assertTrue(database.ledger().outbox("guest").isEmpty())
            assertNull(database.ledger().receipt("guest", "create"))
            restoreOutboxSpace(database)
            repository.importOwner("guest", backup)
            assertEquals(backup, repository.exportOwner("guest"))
        }
    }

    @Test fun `synced legacy outbox preserves acknowledgements despite stale pending record status`() = runBlocking<Unit> {
        val source = directory.resolve("synced-legacy.db")
        val fixture = Json.parseToJsonElement(Files.readString(Path.of("../../../tests/fixtures/legacy/v1.json"))).jsonObject
        val connection = BundledSQLiteDriver().open(source.toString())
        try {
            fixture.getValue("statements").jsonArray.forEach { connection.execSQL(it.jsonPrimitive.content) }
            connection.execSQL("UPDATE sync_outbox SET is_synced = 1")
        } finally { connection.close() }
        openLocalDatabase(directory.resolve("synced-target.db").toString()).use { database ->
            val repository = LocalRepository(database)
            assertTrue(repository.importLegacy(source.toString(), "guest", mapOf("walk" to "Asia/Shanghai"), true).imported)
            assertTrue(database.ledger().outbox("guest").isEmpty())
            assertNotNull(database.ledger().receipt("guest", "legacy-complete"))
            assertEquals(1, database.ledger().checkIns("guest", "walk").size)
            assertTrue(repository.importLegacy(source.toString(), "guest", mapOf("walk" to "Asia/Shanghai"), true).imported)
            assertTrue(database.ledger().outbox("guest").isEmpty())
        }
    }

    @Test fun `v1 upgrades preserve habits credit pending events and retry receipts`() = runBlocking<Unit> {
        val path = directory.resolve("upgrade.db").toString()
        val original = habit().copy(goalKind = "steps", target = 1000.0)
        val command = CompletionCommand("guest", "complete", "entry", "walk", instant, 1000.0)
        val credit = CalendarPolicy.credit(Instant.ofEpochMilli(instant), original.zoneId)
        val preservedRecord = createPriorDatabase(path, Files.readString(
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

    @Test fun `v2 upgrade preserves pending records and adds durable deletion fencing`() = runBlocking<Unit> {
        val path = directory.resolve("upgrade-v2.db").toString()
        val command = CompletionCommand("guest", "complete", "entry", "walk", instant, null)
        val original = createPriorDatabase(path, Files.readString(Path.of("schemas/com.dailygo.storage.LocalDatabase/2.json")), habit(), command)
        openLocalDatabase(path).use { database ->
            val repository = LocalRepository(database)
            assertEquals(original, repository.complete(command))
            assertEquals(2, database.ledger().outbox("guest").size)
            repository.deleteOwner("guest")
        }
        openLocalDatabase(path).use { database ->
            assertTrue(database.ledger().isDeleted("guest"))
            assertTrue(database.ledger().habits("guest").isEmpty())
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