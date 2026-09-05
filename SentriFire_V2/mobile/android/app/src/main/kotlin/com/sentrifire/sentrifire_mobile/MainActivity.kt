package com.sentrifire.sentrifire_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()
            val channel = NotificationChannel(
                "sentrifire_critical_alerts",
                "Critical Fire Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Confirmed and critical SentriFire alerts"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500, 250, 1000)
                setSound(alarmSound, attributes)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
