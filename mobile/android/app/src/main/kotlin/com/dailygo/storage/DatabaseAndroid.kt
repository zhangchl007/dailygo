package com.dailygo.storage

import android.content.Context
import androidx.room.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers

fun openLocalDatabase(context: Context, name: String = "dailygo-native.db"): LocalDatabase {
    require(name.matches(Regex("[A-Za-z0-9_.-]{1,80}")) && !name.contains("..")) { "Invalid database name" }
    val application = context.applicationContext
    val file = application.getDatabasePath(name)
    val directory = requireNotNull(file.parentFile)
    check(directory.isDirectory || directory.mkdirs()) { "Database directory unavailable" }
    return Room.databaseBuilder(application, LocalDatabase::class.java, file.absolutePath)
        .setDriver(BundledSQLiteDriver())
        .setQueryCoroutineContext(Dispatchers.IO)
        .build()
}