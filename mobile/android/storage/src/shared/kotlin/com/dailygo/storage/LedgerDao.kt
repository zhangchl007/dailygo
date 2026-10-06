package com.dailygo.storage

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface LedgerDao {
    @Insert suspend fun insertHabit(habit: HabitRow)
    @Update suspend fun updateHabit(habit: HabitRow): Int
    @Insert suspend fun insertCheckIn(record: CheckInRow)
    @Insert suspend fun insertProgress(record: ProgressRow)
    @Insert suspend fun insertOutbox(event: OutboxRow)
    @Insert suspend fun insertReceipt(receipt: MutationReceiptRow)
    @Insert suspend fun insertDeletedOwner(owner: DeletedOwnerRow)

    @Query("SELECT EXISTS(SELECT 1 FROM deleted_owners WHERE ownerId = :ownerId)")
    suspend fun isDeleted(ownerId: String): Boolean

    @Query("DELETE FROM habits WHERE ownerId = :ownerId")
    suspend fun deleteHabits(ownerId: String)

    @Query("DELETE FROM outbox WHERE ownerId = :ownerId")
    suspend fun deleteEvents(ownerId: String)

    @Query("DELETE FROM mutation_receipts WHERE ownerId = :ownerId")
    suspend fun deleteReceipts(ownerId: String)

    @Query("SELECT * FROM check_ins WHERE ownerId = :ownerId ORDER BY id")
    suspend fun allCheckIns(ownerId: String): List<CheckInRow>

    @Query("SELECT * FROM progress_entries WHERE ownerId = :ownerId ORDER BY id")
    suspend fun allProgress(ownerId: String): List<ProgressRow>

    @Query("SELECT * FROM mutation_receipts WHERE ownerId = :ownerId ORDER BY operationId")
    suspend fun allReceipts(ownerId: String): List<MutationReceiptRow>

    @Query("SELECT * FROM habits WHERE ownerId = :ownerId AND id = :id")
    suspend fun habit(ownerId: String, id: String): HabitRow?

    @Query("SELECT * FROM habits WHERE ownerId = :ownerId ORDER BY createdAtMillis, id")
    suspend fun habits(ownerId: String): List<HabitRow>

    @Query("SELECT * FROM check_ins WHERE ownerId = :ownerId AND habitId = :habitId ORDER BY creditedDate, id")
    suspend fun checkIns(ownerId: String, habitId: String): List<CheckInRow>

    @Query("SELECT * FROM check_ins WHERE ownerId = :ownerId AND id = :id")
    suspend fun checkIn(ownerId: String, id: String): CheckInRow?

    @Query("SELECT * FROM check_ins WHERE ownerId = :ownerId AND habitId = :habitId AND creditedDate = :date")
    suspend fun completionOn(ownerId: String, habitId: String, date: String): CheckInRow?

    @Query("SELECT * FROM progress_entries WHERE ownerId = :ownerId AND habitId = :habitId ORDER BY creditedDate, occurredAtMillis, id")
    suspend fun progressEntries(ownerId: String, habitId: String): List<ProgressRow>

    @Query("SELECT * FROM progress_entries WHERE ownerId = :ownerId AND id = :id")
    suspend fun progress(ownerId: String, id: String): ProgressRow?

    @Query("SELECT * FROM outbox WHERE ownerId = :ownerId ORDER BY createdAtMillis, eventId")
    suspend fun outbox(ownerId: String): List<OutboxRow>

    @Query("SELECT * FROM mutation_receipts WHERE ownerId = :ownerId AND operationId = :operationId")
    suspend fun receipt(ownerId: String, operationId: String): MutationReceiptRow?

    @Query("DELETE FROM outbox WHERE ownerId = :ownerId AND eventId = :eventId")
    suspend fun acknowledge(ownerId: String, eventId: String)
}