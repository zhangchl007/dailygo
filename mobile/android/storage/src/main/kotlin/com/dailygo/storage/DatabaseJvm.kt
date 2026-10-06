package com.dailygo.storage

import androidx.room.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers

fun openLocalDatabase(path: String): LocalDatabase = Room.databaseBuilder<LocalDatabase>(
    name = path,
    factory = { LocalDatabase_Impl() },
).setDriver(BundledSQLiteDriver()).setQueryCoroutineContext(Dispatchers.IO).build()