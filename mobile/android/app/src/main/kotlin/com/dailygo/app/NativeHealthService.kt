package com.dailygo.app

import android.content.Context
import android.content.pm.PackageManager
import android.health.connect.AggregateRecordsRequest
import android.health.connect.AggregateRecordsResponse
import android.health.connect.HealthConnectException
import android.health.connect.HealthConnectManager
import android.health.connect.TimeInstantRangeFilter
import android.health.connect.datatypes.StepsRecord
import android.os.Build
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import com.dailygo.domain.HealthEvidence
import com.dailygo.domain.HealthReadWindow
import com.dailygo.domain.HealthSource
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

enum class NativeHealthReadStatus { UNAVAILABLE, PERMISSION_REQUIRED, UNKNOWN, AVAILABLE, FAILED }

data class NativeHealthReading(
    val status: NativeHealthReadStatus,
    val evidence: HealthEvidence? = null,
    val sourceIdentifiers: Set<String> = emptySet(),
)

class NativeHealthService(private val context: Context) {
    suspend fun readSteps(window: HealthReadWindow): NativeHealthReading {
        if (Build.VERSION.SDK_INT < 34) return NativeHealthReading(NativeHealthReadStatus.UNAVAILABLE)
        return readPlatformSteps(window)
    }

    @RequiresApi(34)
    private suspend fun readPlatformSteps(window: HealthReadWindow): NativeHealthReading {
        val manager = context.getSystemService(HealthConnectManager::class.java)
            ?: return NativeHealthReading(NativeHealthReadStatus.UNAVAILABLE)
        if (context.checkSelfPermission(stepPermission) != PackageManager.PERMISSION_GRANTED) {
            return NativeHealthReading(NativeHealthReadStatus.PERMISSION_REQUIRED)
        }
        val filter = TimeInstantRangeFilter.Builder().setStartTime(window.startedAt).setEndTime(window.endedAt).build()
        val request = AggregateRecordsRequest.Builder<Long>(filter).addAggregationType(StepsRecord.STEPS_COUNT_TOTAL).build()
        return suspendCancellableCoroutine { continuation ->
            val callback = object : OutcomeReceiver<AggregateRecordsResponse<Long>, HealthConnectException> {
                override fun onResult(result: AggregateRecordsResponse<Long>) {
                    if (!continuation.isActive) return
                    val steps = result.get(StepsRecord.STEPS_COUNT_TOTAL)
                    val sources = result.getDataOrigins(StepsRecord.STEPS_COUNT_TOTAL).map { it.packageName }.toSet()
                    if (steps == null || sources.isEmpty()) {
                        continuation.resume(NativeHealthReading(NativeHealthReadStatus.UNKNOWN))
                    } else {
                        val evidence = runCatching { HealthEvidence(HealthSource.HEALTH_CONNECT, window.startedAt,
                            window.endedAt, steps = steps.toDouble()) }.getOrNull()
                        continuation.resume(if (evidence == null) NativeHealthReading(NativeHealthReadStatus.FAILED)
                            else NativeHealthReading(NativeHealthReadStatus.AVAILABLE, evidence, sources))
                    }
                }

                override fun onError(error: HealthConnectException) {
                    if (!continuation.isActive) return
                    continuation.resume(NativeHealthReading(if (error.errorCode == HealthConnectException.ERROR_SECURITY)
                        NativeHealthReadStatus.PERMISSION_REQUIRED else NativeHealthReadStatus.FAILED))
                }
            }
            try {
                manager.aggregate(request, context.mainExecutor, callback)
            } catch (_: SecurityException) {
                if (continuation.isActive) continuation.resume(NativeHealthReading(NativeHealthReadStatus.PERMISSION_REQUIRED))
            } catch (_: RuntimeException) {
                if (continuation.isActive) continuation.resume(NativeHealthReading(NativeHealthReadStatus.FAILED))
            }
        }
    }

    companion object {
        const val stepPermission = "android.permission.health.READ_STEPS"
    }
}