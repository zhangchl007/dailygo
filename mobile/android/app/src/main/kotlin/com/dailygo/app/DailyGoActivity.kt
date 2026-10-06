package com.dailygo.app

import android.app.Application
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModel
import com.dailygo.BuildConfig
import com.dailygo.R
import com.dailygo.storage.*
import com.dailygo.domain.Schedule
import com.dailygo.domain.StreakCalculator
import com.dailygo.domain.StreakSummary
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow

class DailyGoApplication : Application() {
    val database by lazy { openLocalDatabase(this) }
    val repository by lazy { LocalRepository(database) }
    private val testRepositories = mutableMapOf<String, LocalRepository>()

    fun repositoryFor(testStore: String?): LocalRepository {
        if (!BuildConfig.DEBUG || testStore == null) return repository
        require(UUID.fromString(testStore).toString() == testStore) { "Invalid test store" }
        return testRepositories.getOrPut(testStore) { LocalRepository(openLocalDatabase(this, "ui-$testStore.db")) }
    }
}

data class HabitScreenState(
    val asOfMillis: Long,
    val habits: List<HabitRow> = emptyList(),
    val completed: Set<String> = emptySet(),
    val completionRecords: Map<String, CheckInRow> = emptyMap(),
    val streaks: Map<String, StreakSummary> = emptyMap(),
    val recentDates: Map<String, Set<LocalDate>> = emptyMap(),
    val loading: Boolean = true,
    val saving: Boolean = false,
    val error: Int? = null,
)

class NativeHabitModel(application: Application, private val repository: LocalRepository, val clock: Clock) : AndroidViewModel(application) {
    val state = MutableStateFlow(HabitScreenState(asOfMillis = clock.millis()))
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun reload() {
        scope.launch {
            try { refresh() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { state.value = state.value.copy(loading = false, error = R.string.storage_error) }
        }
    }

    private suspend fun refresh() {
        val now = clock.instant()
        val snapshot = withContext(Dispatchers.IO) {
            val habits = repository.habits("guest")
            val dates = habits.associate { habit -> habit.id to repository.completionDates("guest", habit.id) }
            val todayByHabit = habits.associate { habit -> habit.id to now.atZone(ZoneId.of(habit.zoneId)).toLocalDate() }
            val streaks = habits.associate { habit ->
                val definition = habit.definition()
                habit.id to StreakCalculator.calculate(definition.schedule, dates.getValue(habit.id), todayByHabit.getValue(habit.id))
            }
            val recent = habits.associate { habit ->
                val today = todayByHabit.getValue(habit.id)
                val rows = repository.recentCheckIns("guest", habit.id, today.minusDays(34).toString(), today.toString())
                habit.id to rows.map { LocalDate.parse(it.creditedDate) }.toSet()
            }
            Triple(habits, dates, Triple(streaks, recent, todayByHabit))
        }
        val completionRecords = withContext(Dispatchers.IO) {
            snapshot.first.mapNotNull { habit ->
                repository.completionRecordOn("guest", habit.id, snapshot.third.third.getValue(habit.id).toString())?.let { habit.id to it }
            }.toMap()
        }
        state.value = state.value.copy(asOfMillis = now.toEpochMilli(), habits = snapshot.first, completionRecords = completionRecords,
            completed = snapshot.second.filter { (habitId, dates) -> dates.contains(snapshot.third.third[habitId]) }.keys,
            streaks = snapshot.third.first, recentDates = snapshot.third.second, loading = false, error = null)
    }

    fun mutate(onSuccess: () -> Unit = {}, operation: suspend (LocalRepository) -> Unit) {
        if (state.value.saving) return
        state.value = state.value.copy(saving = true, error = null)
        scope.launch {
            try {
                withContext(Dispatchers.IO) { operation(repository) }
                onSuccess()
                try { refresh() }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (_: Exception) { state.value = state.value.copy(error = R.string.load_error) }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: IllegalArgumentException) { state.value = state.value.copy(error = R.string.validation_error) }
            catch (_: Exception) { state.value = state.value.copy(error = R.string.storage_error) }
            finally { state.value = state.value.copy(saving = false) }
        }
    }

    override fun onCleared() { scope.cancel() }
}

class DailyGoActivity : ComponentActivity() {
    private val model by lazy {
        val testStore = if (BuildConfig.DEBUG) intent.getStringExtra("dailygo.uiTestStore") else null
        val factory = object : ViewModelProvider.Factory {
            override fun <Model : ViewModel> create(modelClass: Class<Model>): Model {
                require(modelClass == NativeHabitModel::class.java)
                val application = application as DailyGoApplication
                val clock = if (testStore == null) Clock.systemDefaultZone()
                    else Clock.fixed(Instant.ofEpochMilli(1_791_282_600_000), ZoneId.of("Asia/Shanghai"))
                return modelClass.cast(NativeHabitModel(application, application.repositoryFor(testStore), clock))
            }
        }
        ViewModelProvider(this, factory)[NativeHabitModel::class.java]
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                DailyGoScreen(model)
            }
        }
    }

    override fun onStart() { super.onStart(); model.reload() }
}

@Composable
fun DailyGoScreen(model: NativeHabitModel) {
    val state by model.state.collectAsState()
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    var progressId by rememberSaveable { mutableStateOf<String?>(null) }
    var deletingId by rememberSaveable { mutableStateOf<String?>(null) }
    var showArchived by rememberSaveable { mutableStateOf(false) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    Scaffold { insets ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(insets).testTag("dailygo-root"),
            contentPadding = PaddingValues(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item { BrandHeader() }
            item {
                Row {
                    Text(stringResource(R.string.today), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    IconButton(onClick = { showSettings = true }) {
                        Icon(painterResource(android.R.drawable.ic_menu_preferences), contentDescription = stringResource(R.string.settings))
                    }
                }
                Text(Instant.ofEpochMilli(state.asOfMillis).atZone(model.clock.zone).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)))
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Button(onClick = { editingId = "" }, enabled = !state.loading && !state.saving) {
                        Icon(painterResource(android.R.drawable.ic_input_add), contentDescription = null)
                        Text(stringResource(R.string.add_habit))
                    }
                    FilterChip(selected = showArchived, onClick = { showArchived = !showArchived }, label = { Text(stringResource(R.string.archived)) })
                }
                Text(stringResource(R.string.habits), style = MaterialTheme.typography.titleMedium)
            }
            if (state.loading) item { CircularProgressIndicator() }
            state.error?.let { error -> item {
                Text(stringResource(error), color = MaterialTheme.colorScheme.error)
                TextButton(onClick = model::reload, enabled = !state.saving) { Text(stringResource(R.string.retry)) }
            } }
            val visible = state.habits.filter { it.archived == showArchived }
            if (!state.loading && state.error == null && visible.isEmpty()) item { Text(stringResource(R.string.no_habits)) }
            items(visible, key = { it.id }) { habit ->
                var expanded by remember { mutableStateOf(false) }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row {
                        Text(habit.title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        Box {
                            IconButton(onClick = { expanded = true }, enabled = !state.saving) {
                                Icon(painterResource(android.R.drawable.ic_menu_more), contentDescription = stringResource(R.string.habit_options))
                            }
                            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                                DropdownMenuItem(text = { Text(stringResource(R.string.edit_habit)) }, onClick = { expanded = false; editingId = habit.id })
                                DropdownMenuItem(text = { Text(stringResource(if (habit.archived) R.string.restore else R.string.archive)) }, onClick = {
                                    expanded = false
                                    val command = HabitArchiveCommand("guest", UUID.randomUUID().toString(), habit.id, !habit.archived, model.clock.millis())
                                    model.mutate { it.setHabitArchived(command) }
                                })
                                DropdownMenuItem(text = { Text(stringResource(R.string.delete_habit)) }, onClick = { expanded = false; deletingId = habit.id })
                            }
                        }
                    }
                    Text("${stringResource(scheduleLabel(habit.scheduleKind))} · ${stringResource(goalLabel(habit.goalKind))}")
                    state.streaks[habit.id]?.let { streak ->
                        val unit = if (streak.unit == com.dailygo.domain.StreakUnit.WEEKS) R.string.weeks else R.string.days
                        Text(stringResource(R.string.current_streak, streak.current, stringResource(unit)))
                    }
                    var showHistory by rememberSaveable(habit.id) { mutableStateOf(false) }
                    TextButton(onClick = { showHistory = !showHistory }) { Text(stringResource(if (showHistory) R.string.hide_history else R.string.show_history)) }
                    if (showHistory) {
                        val today = Instant.ofEpochMilli(state.asOfMillis).atZone(ZoneId.of(habit.zoneId)).toLocalDate()
                        Column(modifier = Modifier.testTag("history-grid"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            (0..4).forEach { week ->
                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    (0..6).forEach { day ->
                                        val date = today.minusDays((34 - (week * 7 + day)).toLong())
                                        val done = date in state.recentDates[habit.id].orEmpty()
                                        val description = "$date: ${stringResource(if (done) R.string.completed else R.string.not_completed)}"
                                        Surface(
                                            modifier = Modifier.size(20.dp).testTag("history-${habit.id}-$date")
                                                .semantics { contentDescription = description },
                                            color = if (done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                                            shape = MaterialTheme.shapes.extraSmall,
                                        ) { }
                                    }
                                }
                            }
                        }
                    }
                    if (!habit.archived) {
                        Button(onClick = {
                            if (habit.goalKind != "completion") progressId = habit.id
                            else {
                                val id = UUID.randomUUID().toString()
                                val command = CompletionCommand("guest", id, id, habit.id, model.clock.millis(), null)
                                model.mutate { it.complete(command) }
                            }
                        }, enabled = !state.saving && habit.id !in state.completionRecords) {
                            Text(stringResource(if (habit.id in state.completed) R.string.completed else if (habit.goalKind == "completion") R.string.complete else R.string.record_progress))
                        }
                        state.completionRecords[habit.id]?.let { entry ->
                            val isActive = habit.id in state.completed
                            TextButton(onClick = {
                                val command = CompletionCorrectionCommand("guest", UUID.randomUUID().toString(), entry.id, !isActive, model.clock.millis())
                                model.mutate { it.correctCompletion(command) }
                            }, enabled = !state.saving) {
                                Text(stringResource(if (isActive) R.string.undo_completion else R.string.restore_completion))
                            }
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }
    if (showSettings) ReminderSettings(onDismiss = { showSettings = false })
    if (editingId != null && !state.loading) {
        HabitEditor(state.habits.find { it.id == editingId }, model, onDismiss = { editingId = null })
    }
    state.habits.find { it.id == progressId }?.let { habit ->
        ProgressEditor(habit, model, onDismiss = { progressId = null })
    }
    state.habits.find { it.id == deletingId }?.let { habit ->
        val operationId = rememberSaveable { UUID.randomUUID().toString() }
        AlertDialog(onDismissRequest = { if (!state.saving) deletingId = null }, title = { Text(stringResource(R.string.delete_habit)) },
            text = { Column {
                Text(stringResource(R.string.delete_confirmation, habit.title))
                state.error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
            } }, confirmButton = { TextButton(modifier = Modifier.testTag("confirm-habit-delete"), enabled = !state.saving, onClick = {
                val command = HabitDeleteCommand("guest", operationId, habit.id, model.clock.millis())
                model.mutate(onSuccess = { deletingId = null }) { it.deleteHabit(command) }
            }) { Text(stringResource(R.string.delete_habit)) } },
            dismissButton = { TextButton(enabled = !state.saving, onClick = { deletingId = null }) { Text(stringResource(R.string.cancel)) } })
    }
}

@Composable
private fun ReminderSettings(onDismiss: () -> Unit) {
    val context = LocalContext.current
    var enabled by rememberSaveable { mutableStateOf(DailyReminder.enabled(context) && DailyReminder.canNotify(context)) }
    var permissionDenied by rememberSaveable { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permissionDenied = !granted
        enabled = granted && DailyReminder.canNotify(context)
        if (enabled) DailyReminder.setEnabled(context, true) else DailyReminder.setEnabled(context, false)
    }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.settings)) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row {
                Column(modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.reminders))
                    Text(stringResource(R.string.reminder_time), style = MaterialTheme.typography.bodySmall)
                }
                Switch(checked = enabled, onCheckedChange = { requested ->
                    permissionDenied = false
                    if (!requested) {
                        enabled = false
                        DailyReminder.setEnabled(context, false)
                    } else if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else if (!DailyReminder.canNotify(context)) {
                        enabled = false
                        permissionDenied = true
                        DailyReminder.setEnabled(context, false)
                    } else {
                        enabled = true
                        DailyReminder.setEnabled(context, true)
                    }
                })
            }
            if (permissionDenied) Text(stringResource(R.string.notification_permission_denied), color = MaterialTheme.colorScheme.error)
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } })
}

private fun scheduleLabel(kind: String) = when (kind) { "weekdays" -> R.string.weekdays; "weekly" -> R.string.weekly; else -> R.string.daily }
private fun goalLabel(kind: String) = when (kind) { "steps" -> R.string.steps; "duration_minutes" -> R.string.duration_minutes; "distance_meters" -> R.string.distance_meters; else -> R.string.completion }

@Composable
private fun Choice(label: Int, value: String, options: List<String>, text: (String) -> Int, onChange: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { expanded = true }) { Text("${stringResource(label)}: ${stringResource(text(value))}") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option -> DropdownMenuItem(text = { Text(stringResource(text(option))) }, onClick = { onChange(option); expanded = false }) }
        }
    }
}

@Composable
private fun HabitEditor(existing: HabitRow?, model: NativeHabitModel, onDismiss: () -> Unit) {
    val state by model.state.collectAsState()
    val id = rememberSaveable { existing?.id ?: UUID.randomUUID().toString() }
    val operationId = rememberSaveable { UUID.randomUUID().toString() }
    var occurred by rememberSaveable { mutableStateOf<Long?>(null) }
    var title by rememberSaveable { mutableStateOf(existing?.title ?: "") }
    var schedule by rememberSaveable { mutableStateOf(existing?.scheduleKind ?: "daily") }
    var weekly by rememberSaveable { mutableStateOf((existing?.scheduleParameter ?: 3).toString()) }
    var goal by rememberSaveable { mutableStateOf(existing?.goalKind ?: "completion") }
    var target by rememberSaveable { mutableStateOf(existing?.target?.toString() ?: "") }
    var zone by rememberSaveable { mutableStateOf(existing?.zoneId ?: model.clock.zone.id) }
    AlertDialog(onDismissRequest = { if (!state.saving) onDismiss() }, title = { Text(stringResource(if (existing == null) R.string.add_habit else R.string.edit_habit)) },
        text = { LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { OutlinedTextField(title, { title = it }, label = { Text(stringResource(R.string.title)) }, modifier = Modifier.testTag("habit-title")) }
            item { Choice(R.string.schedule, schedule, listOf("daily", "weekdays", "weekly"), ::scheduleLabel) { schedule = it } }
            if (schedule == "weekly") item { OutlinedTextField(weekly, { weekly = it }, label = { Text(stringResource(R.string.weekly_target)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)) }
            if (existing == null) item { Choice(R.string.goal, goal, listOf("completion", "steps", "duration_minutes", "distance_meters"), ::goalLabel) { goal = it } }
            if (goal != "completion") item { OutlinedTextField(target, { target = it }, readOnly = existing != null, label = { Text(stringResource(R.string.target)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)) }
            item { OutlinedTextField(zone, { zone = it }, label = { Text(stringResource(R.string.timezone)) }) }
            state.error?.let { error -> item { Text(stringResource(error), color = MaterialTheme.colorScheme.error) } }
        } },
        confirmButton = { TextButton(enabled = !state.saving, onClick = {
            val instant = occurred ?: model.clock.millis().also { occurred = it }
            val titleValue = title.trim()
            val scheduleValue = schedule
            val weeklyValue = weekly
            val goalValue = goal
            val targetValue = target
            val zoneValue = zone
            val asOf = model.clock.millis()
            model.mutate(onSuccess = onDismiss) { repository ->
                val parameter = if (scheduleValue == "weekly") requireNotNull(weeklyValue.toIntOrNull()) else null
                if (existing == null) repository.saveHabit(HabitRow("guest", id, titleValue, scheduleValue, parameter, goalValue,
                    if (goalValue == "completion") null else requireNotNull(targetValue.toDoubleOrNull()), zoneValue, instant, false), operationId)
                else repository.editHabit(HabitEditCommand("guest", operationId, id, titleValue, scheduleValue, parameter, zoneValue, instant, asOf))
            }
        }) { Text(stringResource(R.string.save)) } },
        dismissButton = { TextButton(enabled = !state.saving, onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun ProgressEditor(habit: HabitRow, model: NativeHabitModel, onDismiss: () -> Unit) {
    val state by model.state.collectAsState()
    val operationId = rememberSaveable { UUID.randomUUID().toString() }
    var occurred by rememberSaveable { mutableStateOf<Long?>(null) }
    var value by rememberSaveable { mutableStateOf("") }
    AlertDialog(onDismissRequest = { if (!state.saving) onDismiss() }, title = { Text(habit.title) }, text = {
        Column {
            Text("${stringResource(R.string.target)}: ${habit.target} ${stringResource(goalLabel(habit.goalKind))}")
            OutlinedTextField(value, { value = it }, label = { Text(stringResource(R.string.manual_value)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
            state.error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
        }
    }, confirmButton = { TextButton(enabled = !state.saving, onClick = {
        val instant = occurred ?: model.clock.millis().also { occurred = it }
        val valueText = value
        val asOf = model.clock.millis()
        model.mutate(onSuccess = onDismiss) { repository ->
            val numeric = requireNotNull(valueText.toDoubleOrNull())
            if (habit.definition().goal.isCompleted(numeric)) repository.complete(CompletionCommand("guest", operationId, operationId, habit.id, instant, numeric, asOfMillis = asOf))
            else repository.recordProgress(ProgressCommand("guest", operationId, operationId, habit.id, instant, numeric, asOfMillis = asOf))
        }
    }) { Text(stringResource(R.string.save)) } }, dismissButton = { TextButton(enabled = !state.saving, onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}
