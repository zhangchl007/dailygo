package com.dailygo.storage

import androidx.room.AutoMigration
import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [HabitRow::class, CheckInRow::class, ProgressRow::class, OutboxRow::class, MutationReceiptRow::class],
    version = 2,
    autoMigrations = [AutoMigration(from = 1, to = 2)],
    exportSchema = true,
)
abstract class LocalDatabase : RoomDatabase() {
    abstract fun ledger(): LedgerDao
}