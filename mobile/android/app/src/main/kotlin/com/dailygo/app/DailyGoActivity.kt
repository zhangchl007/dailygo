package com.dailygo.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.dailygo.R
import java.time.Clock
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

class DailyGoActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val overview = AppOverview.empty(Clock.systemDefaultZone())
        setContent {
            MaterialTheme {
                DailyGoScreen(overview)
            }
        }
    }
}

@Composable
fun DailyGoScreen(overview: AppOverview) {
    Scaffold { insets ->
        Column(
            modifier = Modifier.fillMaxSize().padding(insets).padding(24.dp).testTag("dailygo-root"),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            BrandHeader()
            Text(stringResource(R.string.today), style = MaterialTheme.typography.titleLarge)
            Text(overview.date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)))
            Text(stringResource(R.string.habits), style = MaterialTheme.typography.titleMedium)
            Text(overview.summary.total.toString(), style = MaterialTheme.typography.headlineMedium)
            Text(stringResource(R.string.no_habits), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}