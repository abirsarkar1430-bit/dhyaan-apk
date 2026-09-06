
package com.dhyaan.app
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
class DhyaanNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try{ if(sbn.packageName=="com.google.android.youtube"){ val extras=sbn.notification.extras; val title=extras.getCharSequence("android.title")?.toString() ?: ""; val text=extras.getCharSequence("android.text")?.toString() ?: ""; val full=if(text.isNotEmpty) "$title - $text" else title; if(full.length>5){ val prefs=applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE); prefs.edit().putString("flutter.flutter.last_yt_title", full).apply() } } } catch(e: Exception){}
    }
}
