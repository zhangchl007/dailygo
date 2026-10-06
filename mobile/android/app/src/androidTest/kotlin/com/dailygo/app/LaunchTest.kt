package com.dailygo.app

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.platform.app.InstrumentationRegistry
import com.dailygo.R
import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class LaunchTest {
    @get:Rule
    val compose = createAndroidComposeRule<DailyGoActivity>()

    @Test
    @OptIn(ExperimentalTestApi::class)
    fun nativeRootIsVisible() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        compose.onNodeWithTag("dailygo-root").assertIsDisplayed()
        compose.onNodeWithTag("dailygo-brand").assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.today)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.habits)).assertIsDisplayed()
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
        compose.onNodeWithText(context.getString(R.string.no_habits)).assertIsDisplayed()
    }
}