package com.dailygo.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.dailygo.R
import java.util.Calendar

object DailyReminder {
    private const val channelId = "daily-reminders"
    private const val requestCode = 47

    fun setEnabled(context: Context, enabled: Boolean) {
        val preferences = context.getSharedPreferences("dailygo-settings", Context.MODE_PRIVATE)
        preferences.edit().putBoolean("reminders-enabled", enabled).apply()
        val intent = PendingIntent.getBroadcast(context, requestCode, Intent(context, DailyReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val alarms = context.getSystemService(AlarmManager::class.java)
        if (!enabled) {
            alarms.cancel(intent)
            return
        }
        val first = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 20)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, first.timeInMillis, intent)
    }

    fun enabled(context: Context) = context.getSharedPreferences("dailygo-settings", Context.MODE_PRIVATE)
        .getBoolean("reminders-enabled", false)

    fun canNotify(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    internal fun notify(context: Context) {
        if (!enabled(context)) return
        if (!canNotify(context)) {
            setEnabled(context, false)
            return
        }
        setEnabled(context, true)
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(channelId, context.getString(R.string.reminders), NotificationManager.IMPORTANCE_DEFAULT))
        val launch = PendingIntent.getActivity(context, requestCode, Intent(context, DailyGoActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = android.app.Notification.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_dailygo_mark)
            .setContentTitle(context.getString(R.string.daily_reminder_title))
            .setContentText(context.getString(R.string.daily_reminder_body))
            .setContentIntent(launch)
            .setAutoCancel(true)
            .build()
        manager.notify(requestCode, notification)
    }
}

class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { DailyReminder.notify(context) }
}

class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED && DailyReminder.enabled(context)) DailyReminder.setEnabled(context, true)
    }
}