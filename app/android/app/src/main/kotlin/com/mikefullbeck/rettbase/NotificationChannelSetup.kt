package com.mikefullbeck.rettbase

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log

/**
 * Android 8+: FCM nutzt [channelId]. Ton kommt vom Kanal (PCM-WAV in res/raw).
 * Pro raw-Ressource: Kanal rett_alarm_w5_<name> mit USAGE_ALARM + optional Bypass DND (API 29+).
 *
 * Kanäle nutzen **R.raw.* Integer-IDs** (nicht Pfad-basierte URIs), weil AAPT2/AGP 8+ die
 * Ressourcennamen obfuskiert (z. B. res/raw/efdn_gong.wav → res/jd.wav). Pfad-basierte URIs
 * wie android.resource://package/raw/efdn_gong finden die umbenannte Datei nicht → Systemton.
 * Die Integer-ID bleibt gültig, da sie über resources.arsc aufgelöst wird.
 *
 * Zusätzlich verhindert res/raw/keep.xml (tools:keep) die Obfuskierung als Fallback.
 *
 * Präfix-Version w5: w4-Kanäle hatten Pfad-basierte URIs, die durch Ressourcen-Obfuskierung
 * nicht auflösten → eingefroren mit Systemton. Neues Präfix erzwingt frische Erstellung.
 *
 * Wird in [RettBaseApplication] aufgerufen, damit Kanäle existieren, bevor MainActivity läuft.
 */
object NotificationChannelSetup {

    // Map: Name → R.raw.* Integer-ID. R8-Inlining der Int-Werte ist OK – die IDs werden direkt
    // verwendet, nicht per Reflection gelesen.
    private val ALARM_TONES: Map<String, Int> = mapOf(
        "efdn_gong" to R.raw.efdn_gong,
        "gong_brand" to R.raw.gong_brand,
        "kleinalarm" to R.raw.kleinalarm,
        "melder1" to R.raw.melder1,
        "ton1" to R.raw.ton1,
        "ton2" to R.raw.ton2,
        "ton3" to R.raw.ton3,
        "ton4" to R.raw.ton4,
    )

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

        // alarm_messages_v2: System-Alarmton + USAGE_ALARM (v1 wurde ohne Sound angelegt – Android friert Kanäle ein).
        val defaultAlarmUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI

        val alarmDefault = NotificationChannel(
            "alarm_messages_v2",
            "Alarmierungen",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Alarmierungen für Einsätze"
            enableVibration(true)
            setSound(defaultAlarmUri, alarmAudioAttrs)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setBypassDnd(true)
            }
        }
        manager.createNotificationChannel(alarmDefault)

        // Pro Alarm-Ton: eigener Kanal mit WAV-Sound aus res/raw (Integer-ID)
        var created = 0
        for ((name, resId) in ALARM_TONES) {
            try {
                val channelId = "rett_alarm_w5_$name"
                // Integer-basierte URI: umgeht Ressourcen-Obfuskierung, da resources.arsc die ID korrekt auflöst
                val soundUri = Uri.parse("android.resource://$packageName/$resId")
                val ch = NotificationChannel(
                    channelId,
                    "Alarm: $name",
                    NotificationManager.IMPORTANCE_HIGH,
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
                created++
                Log.d("RettBase", "Alarm-Kanal erstellt: $channelId → $soundUri (resId=$resId)")
            } catch (e: Exception) {
                Log.w("RettBase", "Alarm-Kanal '$name' übersprungen: ${e.message}")
            }
        }
        Log.i("RettBase", "NotificationChannelSetup: $created/${ALARM_TONES.size} Alarm-Kanäle erstellt")
    }
}
