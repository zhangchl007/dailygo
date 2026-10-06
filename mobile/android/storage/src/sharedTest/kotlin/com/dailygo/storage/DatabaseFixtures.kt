package com.dailygo.storage

import androidx.sqlite.SQLiteConnection
import androidx.room.useWriterConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.dailygo.domain.CalendarPolicy
import java.time.Instant
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

fun createPriorDatabase(path: String, schemaText: String, habit: HabitRow, command: CompletionCommand): CheckInRow {
    val json = Json { encodeDefaults = true }
    val schema = Json.parseToJsonElement(schemaText).jsonObject.getValue("database").jsonObject
    val version = schema.getValue("version").jsonPrimitive.content.toInt()
    require(version in 1..2)
    val credit = CalendarPolicy.credit(Instant.ofEpochMilli(command.occurredAtMillis), habit.zoneId)
    val record = CheckInRow(command.ownerId, command.recordId, command.habitId, command.occurredAtMillis,
        credit.date.toString(), credit.zoneId, credit.reason.name, command.value)
    val habitRequest = json.encodeToString(habit)
    val completionRequest = json.encodeToString(command.copy(asOfMillis = command.occurredAtMillis))
    val connection = BundledSQLiteDriver().open(path)
    try {
        connection.execSQL("BEGIN IMMEDIATE")
        for (entity in schema.getValue("entities").jsonArray) {
            val table = entity.jsonObject
            val tableName = table.getValue("tableName").jsonPrimitive.content
            connection.execSQL(table.getValue("createSql").jsonPrimitive.content.replace("\${TABLE_NAME}", tableName))
            for (index in table["indices"]?.jsonArray.orEmpty()) {
                connection.execSQL(index.jsonObject.getValue("createSql").jsonPrimitive.content.replace("\${TABLE_NAME}", tableName))
            }
        }
        for (query in schema.getValue("setupQueries").jsonArray) connection.execSQL(query.jsonPrimitive.content)
        connection.execSQL("PRAGMA user_version = $version")
        connection.insertFixture("habits", Json.parseToJsonElement(habitRequest).jsonObject)
        connection.insertFixture("check_ins", Json.parseToJsonElement(json.encodeToString(record)).jsonObject)
        for (event in listOf(
            OutboxRow(habit.ownerId, "create", "habit.created", habit.id, habitRequest, habit.createdAtMillis),
            OutboxRow(command.ownerId, command.operationId, "checkin.completed", record.id, json.encodeToString(record), command.occurredAtMillis),
        )) connection.insertFixture("outbox", Json.parseToJsonElement(json.encodeToString(event)).jsonObject)
        for (receipt in listOf(
            MutationReceiptRow(habit.ownerId, "create", "habit.created", habitRequest, habit.id),
            MutationReceiptRow(command.ownerId, command.operationId, "checkin.completed", completionRequest, record.id),
        )) connection.insertFixture("mutation_receipts", Json.parseToJsonElement(json.encodeToString(receipt)).jsonObject)
        connection.execSQL("COMMIT")
    } finally { connection.close() }
    return record
}

suspend fun constrainOutboxSpace(database: LocalDatabase) {
    database.useWriterConnection { connection ->
        connection.usePrepared("CREATE TABLE disk_pressure (payload BLOB)") { it.step() }
        connection.usePrepared("CREATE TRIGGER exhaust_space AFTER INSERT ON outbox BEGIN INSERT INTO disk_pressure VALUES(zeroblob(1048576)); END") { it.step() }
        val pages = connection.usePrepared("PRAGMA page_count") { it.step(); it.getLong(0) }
        connection.usePrepared("PRAGMA max_page_count = $pages") { it.step() }
    }
}

suspend fun restoreOutboxSpace(database: LocalDatabase) {
    database.useWriterConnection { connection ->
        connection.usePrepared("PRAGMA max_page_count = 1073741823") { it.step() }
        connection.usePrepared("DROP TRIGGER exhaust_space") { it.step() }
        connection.usePrepared("DROP TABLE disk_pressure") { it.step() }
    }
}

private fun SQLiteConnection.insertFixture(table: String, row: JsonObject) {
    val columns = row.keys.joinToString(",") { "`$it`" }
    val placeholders = row.keys.joinToString(",") { "?" }
    val statement = prepare("INSERT INTO `$table` ($columns) VALUES ($placeholders)")
    try {
        row.values.forEachIndexed { index, element ->
            val position = index + 1
            if (element == JsonNull) {
                statement.bindNull(position)
            } else {
                val primitive = element.jsonPrimitive
                when {
                    primitive.isString -> statement.bindText(position, primitive.content)
                    primitive.content == "true" -> statement.bindLong(position, 1)
                    primitive.content == "false" -> statement.bindLong(position, 0)
                    primitive.content.toLongOrNull() != null -> statement.bindLong(position, primitive.content.toLong())
                    else -> statement.bindDouble(position, primitive.content.toDouble())
                }
            }
        }
        statement.step()
    } finally { statement.close() }
}