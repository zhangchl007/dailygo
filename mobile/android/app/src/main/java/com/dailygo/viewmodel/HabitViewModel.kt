package com.dailygo.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.dailygo_ffi.*
import java.io.File
import java.time.ZoneId
import java.time.ZonedDateTime

class HabitViewModel(application: Application) : AndroidViewModel(application) {
    private var engine: DailyGoEngineFfi? = null

    private val _habits = MutableStateFlow<List<HabitFfi>>(emptyList())
    val habits: StateFlow<List<HabitFfi>> = _habits.asStateFlow()

    private val _streaks = MutableStateFlow<Map<String, StreakSummaryFfi>>(emptyMap())
    val streaks: StateFlow<Map<String, StreakSummaryFfi>> = _streaks.asStateFlow()

    init {
        val dbFile = File(application.filesDir, "dailygo_local.sqlite")
        try {
            engine = createEngine(dbFile.absolutePath)
            loadHabits()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun loadHabits() {
        viewModelScope.launch {
            engine?.let { eng ->
                val list = eng.listActiveHabits()
                _habits.value = list
                val streakMap = mutableMapOf<String, StreakSummaryFfi>()
                for (h in list) {
                    streakMap[h.id] = eng.getStreak(h.id)
                }
                _streaks.value = streakMap
            }
        }
    }

    fun addHabit(title: String, targetSteps: UInt) {
        viewModelScope.launch {
            engine?.let { eng ->
                eng.createHabit(
                    title = title,
                    frequency = HabitFrequencyFfi.DAILY,
                    metric = MetricTypeFfi.Steps(targetSteps)
                )
                loadHabits()
            }
        }
    }

    fun checkIn(habitId: String, sensorData: HealthSnapshotFfi?) {
        viewModelScope.launch {
            engine?.let { eng ->
                val tzOffset = ZonedDateTime.now(ZoneId.systemDefault()).offset.totalSeconds / 60
                eng.checkIn(
                    habitId = habitId,
                    value = null,
                    sensorData = sensorData,
                    tzOffsetMinutes = tzOffset
                )
                loadHabits()
            }
        }
    }
}
