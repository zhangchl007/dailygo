package com.dailygo.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.dailygo.viewmodel.HabitViewModel
import uniffi.dailygo_ffi.HabitFfi
import uniffi.dailygo_ffi.StreakSummaryFfi

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(viewModel: HabitViewModel) {
    val habits by viewModel.habits.collectAsState()
    val streaks by viewModel.streaks.collectAsState()
    var newHabitTitle by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("DailyGo 运动打卡") }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(16.dp)
        ) {
            LazyColumn(modifier = Modifier.weight(1f)) {
                items(habits) { habit ->
                    val streak = streaks[habit.id]
                    HabitCard(
                        habit = habit,
                        streak = streak,
                        onCheckIn = {
                            viewModel.checkIn(habit.id, null)
                        }
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = newHabitTitle,
                    onValueChange = { newHabitTitle = it },
                    label = { Text("习惯名称 (如: 晨跑 5km)") },
                    modifier = Modifier.weight(1f)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Button(onClick = {
                    if (newHabitTitle.isNotBlank()) {
                        viewModel.addHabit(newHabitTitle, 5000u)
                        newHabitTitle = ""
                    }
                }) {
                    Text("添加")
                }
            }
        }
    }
}

@Composable
fun HabitCard(
    habit: HabitFfi,
    streak: StreakSummaryFfi?,
    onCheckIn: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text(text = habit.title, style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "🔥 ${streak?.currentStreak ?: 0} 天连胜 | 🛡️ 护盾: ${streak?.shieldsRemaining ?: 0}",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.Gray
                )
            }

            Button(
                onClick = onCheckIn,
                enabled = streak?.isCheckedInToday != true
            ) {
                Text(if (streak?.isCheckedInToday == true) "已打卡" else "打卡")
            }
        }
    }
}
