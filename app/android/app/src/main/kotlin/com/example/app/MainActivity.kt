package com.example.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val chatChannel = NotificationChannel(
                "chat_messages",
                "Chat-Nachrichten",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Benachrichtigungen für neue Chat-Nachrichten"
                enableVibration(true)
            }
            manager?.createNotificationChannel(chatChannel)
            val alarmChannel = NotificationChannel(
                "alarm_messages",
                "Alarmierungen",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarmierungen für Einsätze (Einsatzverwaltung)"
                enableVibration(true)
            }
            manager?.createNotificationChannel(alarmChannel)
        }
    }
}
