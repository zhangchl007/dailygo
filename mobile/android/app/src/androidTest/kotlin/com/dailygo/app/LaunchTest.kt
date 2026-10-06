package com.dailygo.app

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import org.junit.Rule
import org.junit.Test

class LaunchTest {
    @get:Rule
    val compose = createAndroidComposeRule<DailyGoActivity>()

    @Test
    fun nativeRootIsVisible() {
        compose.onNodeWithTag("dailygo-root").assertIsDisplayed()
        compose.onNodeWithTag("dailygo-brand").assertIsDisplayed()
    }
}