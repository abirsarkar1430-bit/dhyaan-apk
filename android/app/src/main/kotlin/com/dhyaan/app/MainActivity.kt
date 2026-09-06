package com.dhyaan.app

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.app.usage.UsageStatsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// NOTE: shared_preferences (Flutter plugin) stores its values in the native
// Android SharedPreferences file named "FlutterSharedPreferences", with every
// key prefixed with "flutter.". We read/write that SAME file here so that
// Dart code (using plain keys like "isStudying") and this native code
// (using "flutter.isStudying") stay in sync.
class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.dhyaan.app/usage"
    private val PREFS_NAME = "FlutterSharedPreferences"
    private val PREFIX = "flutter."

    private fun prefs(): SharedPreferences =
        applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllAppsUsage" -> result.success(getAllAppsUsage())
                "getYoutubeUsage" -> result.success(getYoutubeUsageMinutes())
                "getOfflineStudyTime" -> result.success(getOfflineStudyMs())
                "hasUsagePermission" -> result.success(hasUsagePermission())
                "hasNotifPermission" -> result.success(hasNotifPermission())
                "openUsageSettings" -> {
                    openUsageSettings()
                    result.success(null)
                }
                "openNotifSettings" -> {
                    openNotifSettings()
                    result.success(null)
                }
                "startStudyService" -> {
                    startStudyService()
                    result.success(null)
                }
                "stopStudyService" -> {
                    stopStudyService()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getAllAppsUsage(): HashMap<String, Long> {
        val usageMap = HashMap<String, Long>()
        try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val cal = java.util.Calendar.getInstance()
            cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
            cal.set(java.util.Calendar.MINUTE, 0)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            val startTime = cal.timeInMillis

            val statsList = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
            if (statsList != null) {
                for (stat in statsList) {
                    val minutes = stat.totalTimeInForeground / 60000L
                    if (minutes >= 1L) {
                        val existing = usageMap[stat.packageName] ?: 0L
                        usageMap[stat.packageName] = existing + minutes
                    }
                }
            }
        } catch (e: Exception) {
            // no-op, return whatever we have
        }
        return usageMap
    }

    private fun getYoutubeUsageMinutes(): Long {
        val all = getAllAppsUsage()
        return all["com.google.android.youtube"] ?: 0L
    }

    private fun getOfflineStudyMs(): Long {
        return prefs().getLong(PREFIX + "offline_study_ms", 0L)
    }

    private fun hasUsagePermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    private fun hasNotifPermission(): Boolean {
        return try {
            val enabledListeners = Settings.Secure.getString(
                contentResolver, "enabled_notification_listeners"
            )
            enabledListeners != null && enabledListeners.contains(packageName)
        } catch (e: Exception) {
            false
        }
    }

    private fun openUsageSettings() {
        try {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    private fun openNotifSettings() {
        try {
            startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    private fun startStudyService() {
        val intent = Intent(this, StudyForegroundService::class.java)
        intent.action = StudyForegroundService.ACTION_START
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopStudyService() {
        val intent = Intent(this, StudyForegroundService::class.java)
        intent.action = StudyForegroundService.ACTION_STOP
        startService(intent)
    }
}
