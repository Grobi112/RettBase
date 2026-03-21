package com.mikefullbeck.rettbase

import android.app.Application

/**
 * Eigenes [Application], damit Notification-Kanäle vor [MainActivity] existieren (FCM Kaltstart).
 * Kein [io.flutter.embedding.android.FlutterApplication]: je nach Flutter/Gradle-Plugin nicht auf dem
 * Kotlin-Classpath; eine normale [Application] reicht für die Flutter-Engine (Start über Activity).
 */
class RettBaseApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NotificationChannelSetup.ensureAll(this)
    }
}
