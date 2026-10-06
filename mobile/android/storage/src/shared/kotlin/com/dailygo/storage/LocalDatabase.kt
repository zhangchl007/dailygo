package com.dailygo.storage

import androidx.room.AutoMigration
import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [HabitRow::class, CheckInRow::class, ProgressRow::class, OutboxRow::class, MutationReceiptRow::class, DeletedOwnerRow::class, DeletedHabitRow::class, CompletionStateRow::class],
    version = 5,
    autoMigrations = [AutoMigration(from = 1, to = 2), AutoMigration(from = 2, to = 3), AutoMigration(from = 3, to = 4), AutoMigration(from = 4, to = 5)],
    exportSchema = true,
)
abstract class LocalDatabase : RoomDatabase() {
    abstract fun ledger(): LedgerDao
}