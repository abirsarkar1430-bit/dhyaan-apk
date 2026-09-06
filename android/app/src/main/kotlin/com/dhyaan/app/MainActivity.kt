
package com.dhyaan.app
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dhyaan.app/usage"
    private lateinit var prefs: SharedPreferences
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when(call.method){
                "getYoutubeUsage" -> { try{ result.success(getAppUsage("com.google.android.youtube")) } catch(e: Exception){ result.success(0L) } }
                "getAllAppsUsage" -> { try{ result.success(getAllUsage()) } catch(e: Exception){ result.success(mapOf<String, Long>()) } }
                "getOfflineStudyTime" -> { try{ result.success(prefs.getLong("flutter.offline_study_ms", 0L)) } catch(e: Exception){ result.success(0L) } }
                "hasUsagePermission" -> { try{ val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager; val end=System.currentTimeMillis(); val start=end-1000*60*60*24; val stats=usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end); result.success(stats!=null && stats.isNotEmpty()) } catch(e: Exception){ result.success(false) } }
                "hasNotifPermission" -> { try{ val enabled=Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""; result.success(enabled.contains(packageName)) } catch(e: Exception){ result.success(false) } }
                "openUsageSettings" -> { try{ startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)); result.success(true) } catch(e: Exception){ result.success(false) } }
                "openNotifSettings" -> { try{ startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(true) } catch(e: Exception){ result.success(false) } }
                else -> result.notImplemented()
            }
        }
    }
    private fun getAppUsage(pkg: String): Long { try{ val usm=getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager; val end=System.currentTimeMillis(); val start=end-1000*60*60*24; val stats=usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end); var total=0L; stats?.forEach{ if(it.packageName==pkg) total+=it.totalTimeInForeground }; return total } catch(e: Exception){ return 0L } }
    private fun getAllUsage(): Map<String, Long> { val map=mutableMapOf<String, Long>(); try{ val usm=getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager; val end=System.currentTimeMillis(); val start=end-1000*60*60*24; val stats=usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end); stats?.forEach{ s-> if(s.totalTimeInForeground>60000){ val prev=map[s.packageName]?:0L; map[s.packageName]=prev+s.totalTimeInForeground } } } catch(e: Exception){}; return map }
    override fun onResume(){ super.onResume(); try{ val lastPause=prefs.getLong("flutter.last_pause_ms",0L); val now=System.currentTimeMillis(); if(lastPause>0){ val diff=now-lastPause; if(diff in 300000..(4*60*60*1000)){ val cur=prefs.getLong("flutter.offline_study_ms",0L); prefs.edit().putLong("flutter.offline_study_ms", cur+diff).apply() } } } catch(e: Exception){} }
    override fun onPause(){ super.onPause(); try{ prefs.edit().putLong("flutter.last_pause_ms", System.currentTimeMillis()).apply() } catch(e: Exception){} }
}
