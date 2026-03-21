package com.mikefullbeck.rettbase

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.mikefullbeck.rettbase/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showAlarmFullScreen" -> {
                    val title = call.argument<String>("title") ?: "Einsatzalarm"
                    val message = call.argument<String>("message") ?: "Einsatz eingegangen"
                    val notificationId = call.argument<Int>("notificationId") ?: 0

                    try {
                        val intent = Intent(this, AlarmActivity::class.java).apply {
                            putExtra("title", title)
                            putExtra("message", message)
                            putExtra("notificationId", notificationId)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        startActivity(intent)
                        Log.d("RettBase.MainActivity", "AlarmActivity gestartet: $title")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("RettBase.MainActivity", "Fehler beim Starten von AlarmActivity: ${e.message}")
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
