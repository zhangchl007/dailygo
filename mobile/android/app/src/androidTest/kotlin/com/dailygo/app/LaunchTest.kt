package com.dailygo.app

import android.graphics.Bitmap
import android.content.Context
import android.content.Intent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onAllNodes
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextClearance
import androidx.test.platform.app.InstrumentationRegistry
import com.dailygo.R
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test

class LaunchTest {
    private val testStore = UUID.randomUUID().toString()

    @get:Rule
    val compose = AndroidComposeTestRule(
        activityRule = ActivityScenarioRule<DailyGoActivity>(
            Intent(ApplicationProvider.getApplicationContext<Context>(), DailyGoActivity::class.java)
                .putExtra("dailygo.uiTestStore", testStore),
        ),
        activityProvider = { rule ->
            var activity: DailyGoActivity? = null
            rule.scenario.onActivity { activity = it }
            requireNotNull(activity)
        },
    )

    private fun awaitText(value: String) {
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodes(hasText(value) and SemanticsMatcher.keyNotDefined(SemanticsProperties.EditableText))
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun awaitGoalEditorClosed() {
        compose.waitUntil(timeoutMillis = 10_000) { compose.onAllNodesWithTag("habit-target").fetchSemanticsNodes().isEmpty() }
    }

    @Test
    @OptIn(ExperimentalTestApi::class)
    fun nativeRootIsVisible() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        compose.onNodeWithTag("dailygo-root").assertIsDisplayed()
        compose.onNodeWithTag("dailygo-brand").assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.today)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.habits)).assertIsDisplayed()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText(context.getString(R.string.no_habits)).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText(context.getString(R.string.no_habits)).assertIsDisplayed()
        val bitmap = compose.onNodeWithTag("dailygo-root").captureToImage().asAndroidBitmap()
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        assertTrue("Startup screenshot must not be blank", pixels.any { it != pixels.first() })
        FileOutputStream(File(context.filesDir, "ci-native-launch.png")).use { output ->
            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
        }
        compose.activityRule.scenario.recreate()
        compose.onNodeWithTag("dailygo-brand").assertIsDisplayed()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText(context.getString(R.string.no_habits)).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText(context.getString(R.string.no_habits)).assertIsDisplayed()
        val title = "UI walk $testStore"
        val edited = "Evening $testStore"
        compose.onNodeWithText(context.getString(R.string.add_habit)).performClick()
        compose.onNodeWithTag("habit-title").performTextInput(title)
        compose.onNodeWithText(context.getString(R.string.save)).performClick()
        awaitText(title)
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.edit_habit)).performClick()
        compose.onNodeWithTag("habit-title").performTextClearance()
        compose.onNodeWithTag("habit-title").performTextInput(edited)
        compose.onNodeWithText(context.getString(R.string.save)).performClick()
        awaitText(edited)
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.archive)).performClick()
        awaitText(context.getString(R.string.no_habits))
        compose.onNodeWithText(context.getString(R.string.archived)).performClick()
        awaitText(edited)
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.restore)).performClick()
        awaitText(context.getString(R.string.no_habits))
        compose.onNodeWithText(context.getString(R.string.archived)).performClick()
        awaitText(edited)
        compose.onNodeWithText(context.getString(R.string.complete)).performClick()
        awaitText(context.getString(R.string.completed))
        compose.onNodeWithText(context.getString(R.string.undo_completion)).performClick()
        awaitText(context.getString(R.string.restore_completion))
        compose.activityRule.scenario.recreate()
        awaitText(context.getString(R.string.restore_completion))
        compose.onNodeWithText(context.getString(R.string.restore_completion)).performClick()
        awaitText(context.getString(R.string.completed))
        compose.onNodeWithText(context.getString(R.string.show_history)).performClick()
        compose.onNodeWithTag("history-grid").assertIsDisplayed()
        compose.onNodeWithContentDescription(context.getString(R.string.completed), substring = true)
            .performScrollTo().assertIsDisplayed()
        compose.activityRule.scenario.recreate()
        awaitText(edited)
        awaitText(context.getString(R.string.completed))
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performScrollTo().performClick()
        compose.onNodeWithText(context.getString(R.string.delete_habit)).performClick()
        compose.onNodeWithTag("confirm-habit-delete").performClick()
        awaitText(context.getString(R.string.no_habits))
    }

    @Test
    fun goalChangesPersistAndRejectInvalidValuesAndRecordedHistory() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val title = "Goal walk $testStore"
        awaitText(context.getString(R.string.no_habits))
        compose.onNodeWithText(context.getString(R.string.add_habit)).performClick()
        compose.onNodeWithTag("habit-title").performTextInput(title)
        compose.onNodeWithText(context.getString(R.string.save)).performClick()
        awaitText(title)
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.edit_goal)).performClick()
        compose.onNodeWithText("${context.getString(R.string.goal)}: ${context.getString(R.string.completion)}").performClick()
        compose.onNodeWithText(context.getString(R.string.steps)).performClick()
        compose.onNodeWithTag("habit-target").performTextInput("-1")
        compose.onNodeWithText(context.getString(R.string.save)).performClick()
        awaitText(context.getString(R.string.validation_error))
        compose.onNodeWithTag("habit-target").performTextClearance()
        compose.onNodeWithTag("habit-target").performTextInput("1000")
        compose.onNodeWithText(context.getString(R.string.save)).performClick()
        awaitText(context.getString(R.string.record_progress))
        compose.activityRule.scenario.recreate()
        awaitText(context.getString(R.string.record_progress))
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.edit_goal)).performClick()
        compose.onNodeWithTag("habit-target").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("1000.0")))
        compose.onNodeWithText(context.getString(R.string.cancel)).performClick()
        awaitGoalEditorClosed()
        compose.onNodeWithText(context.getString(R.string.record_progress)).performClick()
        compose.onNodeWithText(context.getString(R.string.manual_value)).performTextInput("100")
        compose.onNodeWithText(context.getString(R.string.save)).performClick()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithText(context.getString(R.string.manual_value)).fetchSemanticsNodes().isEmpty()
        }
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.edit_goal)).performClick()
        compose.onNodeWithTag("habit-target").performTextClearance()
        compose.onNodeWithTag("habit-target").performTextInput("2000")
        compose.onNodeWithText(context.getString(R.string.save)).performClick()
        awaitText(context.getString(R.string.goal_history_error))
        compose.onNodeWithText(context.getString(R.string.cancel)).performClick()
        awaitGoalEditorClosed()
        compose.activityRule.scenario.recreate()
        awaitText(title)
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.edit_goal)).performClick()
        compose.onNodeWithTag("habit-target").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("1000.0")))
        val repository = (compose.activity.application as DailyGoApplication).repositoryFor(testStore)
        kotlinx.coroutines.runBlocking {
            val habit = repository.habits("guest").single()
            org.junit.Assert.assertEquals(title, habit.title)
            org.junit.Assert.assertEquals("steps", habit.goalKind)
            org.junit.Assert.assertEquals(1000.0, habit.target)
        }
    }

    @Test
    fun healthReadDoesNotInventSamplesWithoutProviderPermission() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val end = java.time.Instant.ofEpochMilli(1_791_282_600_000)
        val window = com.dailygo.domain.HealthReadWindow(end.minusSeconds(3600), end, end)
        val reading = kotlinx.coroutines.runBlocking { NativeHealthService(context).readSteps(window) }
        if (android.os.Build.VERSION.SDK_INT < 34) {
            org.junit.Assert.assertEquals(NativeHealthReadStatus.UNAVAILABLE, reading.status)
        }
        if (reading.status == NativeHealthReadStatus.AVAILABLE) {
            org.junit.Assert.assertNotNull(reading.evidence)
            assertTrue(reading.sourceIdentifiers.isNotEmpty())
            org.junit.Assert.assertEquals(window.startedAt, reading.evidence?.startedAt)
            org.junit.Assert.assertEquals(window.endedAt, reading.evidence?.endedAt)
        } else {
            org.junit.Assert.assertNull(reading.evidence)
            assertTrue(reading.sourceIdentifiers.isEmpty())
        }
    }

    @Test
    fun reminderPreferenceCannotClaimDeliveryWithoutPermission() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        try {
            DailyReminder.setEnabled(context, true)
            org.junit.Assert.assertEquals(DailyReminder.canNotify(context), DailyReminder.enabled(context))
            compose.activityRule.scenario.recreate()
            org.junit.Assert.assertEquals(DailyReminder.canNotify(context), DailyReminder.enabled(context))
        } finally {
            DailyReminder.setEnabled(context, false)
        }
    }

    @Test
    fun remindersAreOptInAndSettingsAreReachable() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        compose.activityRule.scenario.onActivity { DailyReminder.setEnabled(it, false) }
        assertFalse(DailyReminder.enabled(context))
        compose.onNodeWithContentDescription(context.getString(R.string.settings)).performClick()
        compose.onNodeWithText(context.getString(R.string.reminders)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.reminder_time)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.done)).performClick()
        assertFalse(DailyReminder.enabled(context))
    }
}