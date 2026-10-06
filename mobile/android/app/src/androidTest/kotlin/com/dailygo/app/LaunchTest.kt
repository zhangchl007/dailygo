package com.dailygo.app

import android.graphics.Bitmap
import android.content.Context
import android.content.Intent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
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
        compose.waitUntil(timeoutMillis = 10_000) { compose.onAllNodesWithText(value).fetchSemanticsNodes().isNotEmpty() }
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
        compose.onNodeWithContentDescription(context.getString(R.string.completed), substring = true).assertIsDisplayed()
        compose.activityRule.scenario.recreate()
        awaitText(edited)
        awaitText(context.getString(R.string.completed))
        compose.onNodeWithContentDescription(context.getString(R.string.habit_options)).performClick()
        compose.onNodeWithText(context.getString(R.string.delete_habit)).performClick()
        compose.onNodeWithTag("confirm-habit-delete").performClick()
        awaitText(context.getString(R.string.no_habits))
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