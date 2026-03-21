package com.mikefullbeck.rettbase

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import android.widget.Button
import android.widget.TextView

/**
 * Full-Screen Alarm-Activity für kritische Einsatz-Alarme.
 * - Zeigt sich auf dem Lock Screen (showWhenLocked + turnScreenOn)
 * - Ignoriert Stummschaltung (über Notification Channel USAGE_ALARM)
 * - Nach Bestätigung/Timeout → schließen und zur Main-Activity zurück
 */
class AlarmActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_alarm)

        val intent = intent
        val title = intent?.getStringExtra("title") ?: "Einsatzalarm"
        val message = intent?.getStringExtra("message") ?: "Einsatz eingegangen"
        val notificationId = intent?.getIntExtra("notificationId", 0) ?: 0

        val titleView = findViewById<TextView>(R.id.alarm_title)
        val messageView = findViewById<TextView>(R.id.alarm_message)
        val acceptButton = findViewById<Button>(R.id.alarm_accept_btn)

        titleView?.text = title
        messageView?.text = message

        // Alarm-Lautstärke auf Maximum setzen
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            audioManager.setStreamVolume(
                AudioManager.STREAM_ALARM,
                maxVolume,
                AudioManager.FLAG_SHOW_UI // Zeigt Lautstärke-Regler auf Bildschirm
            )
            Log.d("RettBase.AlarmActivity", "Alarm-Lautstärke auf Maximum gesetzt ($maxVolume)")
        } catch (e: Exception) {
            Log.w("RettBase.AlarmActivity", "Fehler beim Setzen der Lautstärke: ${e.message}")
        }

        acceptButton?.setOnClickListener {
            Log.d("RettBase.AlarmActivity", "Alarm bestätigt")
            // Benachrichtigung entfernen
            if (notificationId != 0) {
                val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notificationId)
            }
            // Zur Main-Activity zurück
            finish()
        }

        // Auto-close nach 30 Sekunden (falls Nutzer nicht reagiert)
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isFinishing) {
                Log.d("RettBase.AlarmActivity", "Auto-close nach 30s")
                finish()
            }
        }, 30000)

        Log.i("RettBase.AlarmActivity", "Alarm angezeigt: $title")
    }
}
