package com.dailygo.storage

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [HabitRow::class, CheckInRow::class, OutboxRow::class, MutationReceiptRow::class],
    version = 1,
    exportSchema = true,
)
abstract class LocalDatabase : RoomDatabase() {
    abstract fun ledger(): LedgerDao
}