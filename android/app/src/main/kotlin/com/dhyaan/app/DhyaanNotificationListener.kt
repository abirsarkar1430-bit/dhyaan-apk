
package com.dhyaan.app

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class DhyaanNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if(sbn == null) return
        if(sbn.packageName != "com.google.android.youtube") return
        val extras = sbn.notification.extras
        val title = extras.getString("android.title") ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val fullTitle = if(text.isNotEmpty()) "$title - $text" else title
        if(fullTitle.length > 5){
            // Send to Flutter via MethodChannel if engine is running
            // For simplicity, save to SharedPreferences and Flutter polls via channel
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            // We also try to broadcast
            try {
                // Store latest title for retrieval
                prefs.edit().putString("flutter.last_yt_title", fullTitle).apply()
            } catch(e: Exception){}
        }
    }
}
