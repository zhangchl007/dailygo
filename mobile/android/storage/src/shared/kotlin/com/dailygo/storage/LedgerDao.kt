package com.dailygo.storage

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert

@Dao
interface LedgerDao {
    @Insert suspend fun insertHabit(habit: HabitRow)
    @Update suspend fun updateHabit(habit: HabitRow): Int
    @Insert suspend fun insertCheckIn(record: CheckInRow)
    @Insert suspend fun insertProgress(record: ProgressRow)
    @Insert suspend fun insertOutbox(event: OutboxRow)
    @Insert suspend fun insertReceipt(receipt: MutationReceiptRow)
    @Update suspend fun updateReceipt(receipt: MutationReceiptRow): Int
    @Insert suspend fun insertDeletedOwner(owner: DeletedOwnerRow)
    @Insert suspend fun insertDeletedHabit(habit: DeletedHabitRow)
    @Upsert suspend fun putCompletionState(state: CompletionStateRow)

    @Query("SELECT * FROM completion_states WHERE ownerId = :ownerId AND recordId = :recordId")
    suspend fun completionState(ownerId: String, recordId: String): CompletionStateRow?

    @Query("SELECT * FROM completion_states WHERE ownerId = :ownerId ORDER BY recordId")
    suspend fun completionStates(ownerId: String): List<CompletionStateRow>

    @Query("SELECT EXISTS(SELECT 1 FROM deleted_habits WHERE ownerId = :ownerId AND habitId = :habitId)")
    suspend fun isHabitDeleted(ownerId: String, habitId: String): Boolean

    @Query("SELECT * FROM deleted_habits WHERE ownerId = :ownerId ORDER BY habitId")
    suspend fun deletedHabits(ownerId: String): List<DeletedHabitRow>

    @Query("DELETE FROM deleted_habits WHERE ownerId = :ownerId")
    suspend fun deleteHabitFences(ownerId: String)

    @Query("DELETE FROM habits WHERE ownerId = :ownerId AND id = :habitId")
    suspend fun deleteHabit(ownerId: String, habitId: String): Int

    @Query("SELECT * FROM mutation_receipts WHERE ownerId = :ownerId AND ((kind LIKE 'habit.%' AND resultId = :habitId) OR (kind IN ('checkin.completed', 'checkin.corrected') AND resultId IN (SELECT id FROM check_ins WHERE ownerId = :ownerId AND habitId = :habitId)) OR (kind = 'progress.recorded' AND resultId IN (SELECT id FROM progress_entries WHERE ownerId = :ownerId AND habitId = :habitId)))")
    suspend fun receiptsForHabit(ownerId: String, habitId: String): List<MutationReceiptRow>

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

    @Query("SELECT DISTINCT creditedDate FROM check_ins c WHERE ownerId = :ownerId AND habitId = :habitId AND NOT EXISTS(SELECT 1 FROM completion_states s WHERE s.ownerId = c.ownerId AND s.recordId = c.id AND s.active = 0) ORDER BY creditedDate")
    suspend fun completionDates(ownerId: String, habitId: String): List<String>

    @Query("SELECT * FROM check_ins c WHERE ownerId = :ownerId AND habitId = :habitId AND creditedDate BETWEEN :startDate AND :endDate AND NOT EXISTS(SELECT 1 FROM completion_states s WHERE s.ownerId = c.ownerId AND s.recordId = c.id AND s.active = 0) ORDER BY creditedDate DESC, id DESC LIMIT :limit")
    suspend fun recentCheckIns(ownerId: String, habitId: String, startDate: String, endDate: String, limit: Int): List<CheckInRow>

    @Query("SELECT * FROM check_ins WHERE ownerId = :ownerId AND id = :id")
    suspend fun checkIn(ownerId: String, id: String): CheckInRow?

    @Query("SELECT * FROM check_ins c WHERE ownerId = :ownerId AND habitId = :habitId AND creditedDate = :date AND NOT EXISTS(SELECT 1 FROM completion_states s WHERE s.ownerId = c.ownerId AND s.recordId = c.id AND s.active = 0)")
    suspend fun completionOn(ownerId: String, habitId: String, date: String): CheckInRow?

    @Query("SELECT * FROM check_ins WHERE ownerId = :ownerId AND habitId = :habitId AND creditedDate = :date")
    suspend fun completionRecordOn(ownerId: String, habitId: String, date: String): CheckInRow?

    @Query("SELECT * FROM progress_entries WHERE ownerId = :ownerId AND habitId = :habitId ORDER BY creditedDate, occurredAtMillis, id")
    suspend fun progressEntries(ownerId: String, habitId: String): List<ProgressRow>

    @Query("SELECT * FROM progress_entries WHERE ownerId = :ownerId AND id = :id")
    suspend fun progress(ownerId: String, id: String): ProgressRow?

    @Query("SELECT EXISTS(SELECT 1 FROM check_ins WHERE ownerId = :ownerId AND habitId = :habitId UNION ALL SELECT 1 FROM progress_entries WHERE ownerId = :ownerId AND habitId = :habitId)")
    suspend fun hasHabitHistory(ownerId: String, habitId: String): Boolean

    @Query("SELECT * FROM outbox WHERE ownerId = :ownerId ORDER BY createdAtMillis, eventId")
    suspend fun outbox(ownerId: String): List<OutboxRow>

    @Query("SELECT * FROM mutation_receipts WHERE ownerId = :ownerId AND operationId = :operationId")
    suspend fun receipt(ownerId: String, operationId: String): MutationReceiptRow?

    @Query("DELETE FROM outbox WHERE ownerId = :ownerId AND eventId = :eventId")
    suspend fun acknowledge(ownerId: String, eventId: String)
}