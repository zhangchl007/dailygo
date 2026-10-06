package com.dailygo.storage

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import kotlinx.serialization.Serializable

@Serializable
@Entity(tableName = "habits", primaryKeys = ["ownerId", "id"], indices = [Index("ownerId", "archived", "createdAtMillis")])
data class HabitRow(
    val ownerId: String,
    val id: String,
    val title: String,
    val scheduleKind: String,
    val scheduleParameter: Int?,
    val goalKind: String,
    val target: Double?,
    val zoneId: String,
    val createdAtMillis: Long,
    val archived: Boolean,
)

@Serializable
@Entity(
    tableName = "check_ins",
    primaryKeys = ["ownerId", "id"],
    foreignKeys = [ForeignKey(
        entity = HabitRow::class, parentColumns = ["ownerId", "id"],
        childColumns = ["ownerId", "habitId"], onDelete = ForeignKey.CASCADE,
    )],
    indices = [Index(value = ["ownerId", "habitId", "creditedDate"], unique = true)],
)
data class CheckInRow(
    val ownerId: String,
    val id: String,
    val habitId: String,
    val occurredAtMillis: Long,
    val creditedDate: String,
    val zoneId: String,
    val creditReason: String,
    val value: Double?,
)

@Serializable
@Entity(
    tableName = "progress_entries",
    primaryKeys = ["ownerId", "id"],
    foreignKeys = [ForeignKey(
        entity = HabitRow::class, parentColumns = ["ownerId", "id"],
        childColumns = ["ownerId", "habitId"], onDelete = ForeignKey.CASCADE,
    )],
    indices = [Index("ownerId", "habitId", "creditedDate", "occurredAtMillis")],
)
data class ProgressRow(
    val ownerId: String,
    val id: String,
    val habitId: String,
    val occurredAtMillis: Long,
    val creditedDate: String,
    val zoneId: String,
    val creditReason: String,
    val value: Double,
)

@Serializable
@Entity(tableName = "outbox", primaryKeys = ["ownerId", "eventId"], indices = [Index("ownerId", "createdAtMillis")])
data class OutboxRow(
    val ownerId: String,
    val eventId: String,
    val kind: String,
    val entityId: String,
    val payload: String,
    val createdAtMillis: Long,
)

@Serializable
@Entity(tableName = "mutation_receipts", primaryKeys = ["ownerId", "operationId"])
data class MutationReceiptRow(
    val ownerId: String,
    val operationId: String,
    val kind: String,
    val request: String,
    val resultId: String,
)

@Entity(tableName = "deleted_owners", primaryKeys = ["ownerId"])
data class DeletedOwnerRow(val ownerId: String)

@Serializable
data class HabitArchiveCommand(
    val ownerId: String,
    val operationId: String,
    val habitId: String,
    val archived: Boolean,
    val occurredAtMillis: Long,
    val asOfMillis: Long = occurredAtMillis,
)

@Serializable
data class CompletionCommand(
    val ownerId: String,
    val operationId: String,
    val recordId: String,
    val habitId: String,
    val occurredAtMillis: Long,
    val value: Double?,
    val workoutStartedAtMillis: Long? = null,
    val asOfMillis: Long = occurredAtMillis,
)

@Serializable
data class ProgressCommand(
    val ownerId: String,
    val operationId: String,
    val recordId: String,
    val habitId: String,
    val occurredAtMillis: Long,
    val value: Double,
    val workoutStartedAtMillis: Long? = null,
    val asOfMillis: Long = occurredAtMillis,
)