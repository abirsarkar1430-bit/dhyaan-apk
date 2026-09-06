package com.dhyaan.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.firebase.Timestamp
import com.google.firebase.firestore.SetOptions

/**
 * Foreground service that keeps a persistent, ongoing notification visible
 * while the student has tapped "Start Studying." This is the ONLY part of
 * the app guaranteed to survive the student closing Dhyaan or swiping it
 * from recents - which is the normal, expected way this app gets used (the
 * student is not meant to keep staring at Dhyaan while studying). Because
 * of that, all the real tracking logic now lives HERE, natively, instead of
 * depending on the Flutter screen staying alive:
 *
 *  - Real screen ON/OFF detection (via a BroadcastReceiver) -> "offline
 *    study" time, credited only when the screen was genuinely off, not just
 *    whenever the Dhyaan app itself lost focus.
 *  - A snapshot of every app's usage minutes taken the moment studying
 *    starts, compared against usage minutes again when studying stops, to
 *    work out exactly which apps were used - and for how long - DURING
 *    this specific study session (separate from generic "all day" usage).
 *  - Weekly study/distraction totals, credited here directly to Firestore
 *    so they update whether or not the student ever reopens the app.
 */
class StudyForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.dhyaan.app.action.START"
        const val ACTION_STOP = "com.dhyaan.app.action.STOP"
        const val CHANNEL_ID = "dhyaan_study"
        const val NOTIF_ID = 1
        private const val DISTRACTION_CHECK_INTERVAL_MS = 5 * 60 * 1000L // every 5 min, to limit Firestore writes
    }

    private val handler = Handler(Looper.getMainLooper())
    private var notificationTicker: Runnable? = null
    private var distractionTicker: Runnable? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var receiverRegistered = false

    private fun p() = DhyaanCore.prefs(this)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                finalizeSession()
                return START_NOT_STICKY
            }
            else -> {
                startSession()
                return START_STICKY
            }
        }
    }

    private fun startSession() {
        createChannelIfNeeded()
        val prefs = p()

        // START_STICKY means Android may kill this service under memory
        // pressure and restart it automatically later - routine on budget
        // phones during a long study session. When that happens, this same
        // startSession() code runs again, but it must NOT be treated like a
        // brand new "Start Studying" tap: a baseline/counter reset at that
        // point would silently throw away everything tracked before the
        // restart. We can tell the difference because a genuinely fresh
        // start never has a baseline snapshot yet.
        val isRestart = prefs.getBoolean(DhyaanCore.PREFIX + "isStudying", false) &&
            prefs.contains(DhyaanCore.PREFIX + "session_baseline_usage")

        prefs.edit().putBoolean(DhyaanCore.PREFIX + "isStudying", true).apply()
        if (!prefs.contains(DhyaanCore.PREFIX + "study_start_ms")) {
            prefs.edit().putLong(DhyaanCore.PREFIX + "study_start_ms", System.currentTimeMillis()).apply()
        }

        if (!isRestart) {
            // Genuine fresh start - snapshot every app's usage-so-far, so we
            // can work out exactly what was used DURING this session by
            // comparing against this baseline later.
            val baseline = DhyaanCore.getAllAppsUsageMinutesToday(this)
            prefs.edit()
                .putString(DhyaanCore.PREFIX + "session_baseline_usage", encodeUsageMap(baseline))
                .putLong(DhyaanCore.PREFIX + "session_credited_distraction_ms", 0L)
                .remove(DhyaanCore.PREFIX + "screen_off_at_ms")
                .apply()
        }
        // else: this is Android resuming an already-in-progress session after
        // killing the process - keep the existing baseline (and any pending
        // screen_off_at_ms, which is still valid wall-clock time even if the
        // process briefly wasn't running) so nothing gets silently lost.

        registerScreenReceiver()
        startForeground(NOTIF_ID, buildNotification(elapsedSeconds()))
        startNotificationTicking()
        startDistractionTicking()
    }

    private fun finalizeSession() {
        // One last distraction-usage check so nothing from the tail end of
        // the session is lost, then write the final per-app breakdown.
        creditSessionDistractionDelta(pushFullSnapshot = true, isFinal = true)

        stopNotificationTicking()
        stopDistractionTicking()
        unregisterScreenReceiver()

        val prefs = p()
        prefs.edit()
            .putBoolean(DhyaanCore.PREFIX + "isStudying", false)
            .remove(DhyaanCore.PREFIX + "study_start_ms")
            .remove(DhyaanCore.PREFIX + "session_baseline_usage")
            .remove(DhyaanCore.PREFIX + "session_credited_distraction_ms")
            .remove(DhyaanCore.PREFIX + "screen_off_at_ms")
            .apply()

        stopForeground(true)
        stopSelf()
    }

    // ------------------------------------------------------------------
    // Real screen on/off detection (accurate "offline study")
    // ------------------------------------------------------------------

    private fun registerScreenReceiver() {
        if (receiverRegistered) return
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        p().edit().putLong(DhyaanCore.PREFIX + "screen_off_at_ms", System.currentTimeMillis()).apply()
                    }
                    Intent.ACTION_SCREEN_ON -> onScreenOn()
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        // Android 13+ (targetSdk 33+) requires an explicit exported flag when
        // dynamically registering a receiver, or this throws at runtime.
        // NOT_EXPORTED is correct here - only the system delivers
        // SCREEN_ON/OFF, no other app needs to be able to send to this receiver.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterScreenReceiver() {
        if (!receiverRegistered) return
        try {
            unregisterReceiver(screenReceiver)
        } catch (e: Exception) {
            // already unregistered - ignore
        }
        receiverRegistered = false
        screenReceiver = null
    }

    private fun onScreenOn() {
        val prefs = p()
        val screenOffAt = prefs.getLong(DhyaanCore.PREFIX + "screen_off_at_ms", -1L)
        if (screenOffAt <= 0) return
        val diffMs = System.currentTimeMillis() - screenOffAt
        val fiveMin = 5 * 60 * 1000L
        val fourHr = 4 * 60 * 60 * 1000L
        if (diffMs in fiveMin..fourHr) {
            val newOffline = prefs.getLong(DhyaanCore.PREFIX + "offline_study_ms", 0L) + diffMs
            prefs.edit().putLong(DhyaanCore.PREFIX + "offline_study_ms", newOffline).apply()
            DhyaanCore.studentDoc(this)?.set(
                mapOf("offlineStudyMs" to newOffline),
                SetOptions.merge()
            )
            DhyaanCore.creditWeeklyStudyMs(this, diffMs)
        }
        prefs.edit().remove(DhyaanCore.PREFIX + "screen_off_at_ms").apply()
    }

    // ------------------------------------------------------------------
    // App usage DURING this study session (for the parent's "what apps did
    // they use while supposed to be studying" view) + weekly distraction credit
    // ------------------------------------------------------------------

    private fun startDistractionTicking() {
        stopDistractionTicking()
        distractionTicker = object : Runnable {
            override fun run() {
                val stillStudying = p().getBoolean(DhyaanCore.PREFIX + "isStudying", false)
                if (!stillStudying) return
                creditSessionDistractionDelta(pushFullSnapshot = true, isFinal = false)
                handler.postDelayed(this, DISTRACTION_CHECK_INTERVAL_MS)
            }
        }
        handler.postDelayed(distractionTicker!!, DISTRACTION_CHECK_INTERVAL_MS)
    }

    private fun stopDistractionTicking() {
        distractionTicker?.let { handler.removeCallbacks(it) }
        distractionTicker = null
    }

    /**
     * Compares current app-usage minutes against the session-start baseline
     * to find out how many minutes of each app were used SINCE studying
     * began. Credits only the NEW increment since the last check to the
     * weekly distraction total (so re-checking doesn't double count), and
     * optionally pushes the full during-session breakdown to Firestore for
     * the parent dashboard.
     */
    private fun creditSessionDistractionDelta(pushFullSnapshot: Boolean, isFinal: Boolean) {
        val prefs = p()
        val baselineStr = prefs.getString(DhyaanCore.PREFIX + "session_baseline_usage", null) ?: return
        val baseline = decodeUsageMap(baselineStr)
        val current = DhyaanCore.getAllAppsUsageMinutesToday(this)

        val duringSession = HashMap<String, Long>()
        var totalDuringSessionMins = 0L
        for ((pkg, mins) in current) {
            if (pkg == packageName) continue // don't count checking Dhyaan itself as a "distraction app"
            val before = baseline[pkg] ?: 0L
            val delta = mins - before
            if (delta >= 1L) {
                duringSession[pkg] = delta
                totalDuringSessionMins += delta
            }
        }

        val alreadyCreditedMs = prefs.getLong(DhyaanCore.PREFIX + "session_credited_distraction_ms", 0L)
        val totalDuringSessionMs = totalDuringSessionMins * 60000L
        val newIncrementMs = totalDuringSessionMs - alreadyCreditedMs
        if (newIncrementMs > 0) {
            DhyaanCore.creditWeeklyDistractionMs(this, newIncrementMs)
            prefs.edit().putLong(DhyaanCore.PREFIX + "session_credited_distraction_ms", totalDuringSessionMs).apply()
        }

        if (pushFullSnapshot) {
            val data: MutableMap<String, Any> = mutableMapOf(
                "lastSessionAppUsage" to duringSession,
                "lastSessionDistractionMins" to totalDuringSessionMins,
                "lastSessionAt" to Timestamp.now()
            )
            if (isFinal) {
                val startMs = prefs.getLong(DhyaanCore.PREFIX + "study_start_ms", System.currentTimeMillis())
                data["lastSessionDurationMins"] = ((System.currentTimeMillis() - startMs) / 60000L)
            }
            DhyaanCore.studentDoc(this)?.set(data, SetOptions.merge())
        }
    }

    private fun encodeUsageMap(map: Map<String, Long>): String =
        map.entries.joinToString(";") { "${it.key}=${it.value}" }

    private fun decodeUsageMap(encoded: String): Map<String, Long> {
        if (encoded.isBlank()) return emptyMap()
        return encoded.split(";").mapNotNull { entry ->
            val parts = entry.split("=")
            if (parts.size == 2) parts[0] to (parts[1].toLongOrNull() ?: 0L) else null
        }.toMap()
    }

    // ------------------------------------------------------------------
    // Ongoing notification (unchanged from before)
    // ------------------------------------------------------------------

    private fun elapsedSeconds(): Long {
        val start = p().getLong(DhyaanCore.PREFIX + "study_start_ms", System.currentTimeMillis())
        return (System.currentTimeMillis() - start) / 1000L
    }

    private fun startNotificationTicking() {
        stopNotificationTicking()
        notificationTicker = object : Runnable {
            override fun run() {
                val stillStudying = p().getBoolean(DhyaanCore.PREFIX + "isStudying", false)
                if (!stillStudying) {
                    stopForeground(true)
                    stopSelf()
                    return
                }
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                try {
                    nm.notify(NOTIF_ID, buildNotification(elapsedSeconds()))
                } catch (e: Exception) {
                    // ignore
                }
                handler.postDelayed(this, 1000L)
            }
        }
        handler.post(notificationTicker!!)
    }

    private fun stopNotificationTicking() {
        notificationTicker?.let { handler.removeCallbacks(it) }
        notificationTicker = null
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Dhyaan Study Tracking",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description = "Shows an ongoing timer while you are studying"
                channel.setShowBadge(false)
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(elapsedSeconds: Long): Notification {
        val h = elapsedSeconds / 3600
        val m = (elapsedSeconds % 3600) / 60
        val s = elapsedSeconds % 60
        val timeStr = String.format("%02d:%02d:%02d", h, m, s)

        val contentIntent = Intent(this, MainActivity::class.java)
        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, StudyForegroundService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = Notification.Builder(this).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                setChannelId(CHANNEL_ID)
            }
            setContentTitle("Dhyaan tracking your study")
            setContentText("$timeStr - Tap to stop")
            setSmallIcon(android.R.drawable.ic_menu_recent_history)
            setOngoing(true)
            setOnlyAlertOnce(true)
            setContentIntent(contentPendingIntent)
            addAction(0, "Stop", stopPendingIntent)
        }

        return builder.build()
    }

    override fun onDestroy() {
        stopNotificationTicking()
        stopDistractionTicking()
        unregisterScreenReceiver()
        super.onDestroy()
    }
}
