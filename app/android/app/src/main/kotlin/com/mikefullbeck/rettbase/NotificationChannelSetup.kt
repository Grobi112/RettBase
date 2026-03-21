package com.mikefullbeck.rettbase

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.util.Log

/**
 * Android 8+: FCM nutzt [channelId]. Ton kommt vom Kanal (PCM-WAV in res/raw, siehe setup_android_sounds.sh).
 * Pro raw-Ressource: Kanal rett_alarm_w_<name> mit USAGE_ALARM + optional Bypass DND (API 29+).
 * MP3 als Kanalton führt auf vielen Geräten zum Fallback auf den Systemton – daher WAV + neues Kanal-Präfix.
 * Wird in [RettBaseApplication] aufgerufen, damit Kanäle existieren, bevor MainActivity läuft.
 */
object NotificationChannelSetup {

    fun ensureAll(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val packageName = context.packageName

        val chatChannel = NotificationChannel(
            "chat_messages",
            "Chat-Nachrichten",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Benachrichtigungen für neue Chat-Nachrichten"
            enableVibration(true)
        }
        manager.createNotificationChannel(chatChannel)

        val alarmAudioAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val alarmDefault = NotificationChannel(
            "alarm_messages",
            "Alarmierungen (Standardton)",
            NotificationManager.IMPORTANCE_MAX,
        ).apply {
            description = "Alarmierungen für Einsätze (Gerätestandard)"
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setBypassDnd(true)
            }
        }
        manager.createNotificationChannel(alarmDefault)

        try {
            for (field in R.raw::class.java.fields) {
                val name = field.name
                if (!name.matches(Regex("[a-z][a-z0-9_]*"))) continue
                val resId = field.getInt(null)
                val channelId = "rett_alarm_w_$name"
                val soundUri = Uri.parse("android.resource://$packageName/$resId")
                val ch = NotificationChannel(
                    channelId,
                    "Alarm: $name",
                    NotificationManager.IMPORTANCE_MAX,
                ).apply {
                    description = "Einsatzalarm ($name)"
                    enableVibration(true)
                    setSound(soundUri, alarmAudioAttrs)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        setBypassDnd(true)
                    }
                }
                manager.createNotificationChannel(ch)
            }
        } catch (e: Exception) {
            Log.w("RettBase", "Alarm-Rohkanäle: ${e.message}")
        }
    }
}
