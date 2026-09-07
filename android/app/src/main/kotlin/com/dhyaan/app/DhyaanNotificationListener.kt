package com.dhyaan.app

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Detects what video YouTube is currently playing, two ways:
 *
 *  1. MEDIA SESSIONS (the main, reliable path) - Android has a system-wide
 *     "what's currently playing" API (the same one that powers lock-screen
 *     media controls and "Hey Google, what song is this"). YouTube publishes
 *     to it whenever ANYTHING plays, foreground or background - unlike
 *     notifications, which YouTube often does NOT post while the app is
 *     actively open and visible (no need for playback controls when you're
 *     already looking at them). This is what actually catches a student
 *     watching YouTube normally, in the foreground, which notifications
 *     alone were missing entirely.
 *
 *     Reading media sessions requires proof of notification-listener access
 *     (passing this service's own ComponentName) - NOT a new/separate
 *     permission, so there's nothing new to ask the student for.
 *
 *  2. NOTIFICATION-BASED (kept as a fallback) - still catches the case where
 *     a notification IS posted (background/lock-screen playback). Both paths
 *     funnel into handleDetectedTitle(), which de-dupes and also watches for
 *     Shorts-style rapid scrolling (see its doc comment below) before either
 *     path reaches the actual save-to-Firestore logic in handleNewTitle() -
 *     having both detection paths active causes no double-processing.
 */
class DhyaanNotificationListener : NotificationListenerService() {

    private val YOUTUBE_PACKAGE = "com.google.android.youtube"
    private val MAX_LOCAL_HISTORY = 40
    private val DEDUPE_WINDOW_MS = 5 * 60 * 1000L
    private val PRUNE_EVERY_N_WRITES = 5

    // Shorts-scrolling detector: rather than needing to catch every single
    // Short's title (genuinely uncertain whether YouTube updates media
    // session metadata cleanly on every rapid swipe), watch for the BEHAVIOR
    // instead - several video changes in quick succession. That pattern
    // itself is the signal, regardless of whether every individual title
    // was caught. Also avoids flooding the parent's history list with
    // dozens of near-identical rapid-fire entries during a real scroll binge.
    private val recentTitleChangeTimestamps = mutableListOf<Long>()
    private val BURST_WINDOW_MS = 45_000L
    private val BURST_THRESHOLD = 3
    private val SHORTS_BURST_TITLE = "YouTube Shorts (rapid scrolling)"

    // Real-device testing surfaced a false-positive: YouTube's home feed
    // auto-plays short, silent PREVIEWS when you pause on a thumbnail while
    // scrolling - you never tapped it, never watched it, but for a second or
    // two YouTube's media session briefly reports it as "now playing." A
    // genuinely watched video stays current for much longer than a scroll-
    // past preview, so before logging a SINGLE video (not a Shorts burst,
    // which is already handled separately above), wait and confirm the
    // title is STILL the current one after a short delay. If it changed
    // again before that, it was almost certainly just a feed preview
    // flicker, not something the student actually watched.
    private val handler = Handler(Looper.getMainLooper())
    private var pendingTitle: String? = null
    private var pendingRunnable: Runnable? = null
    private val MIN_WATCH_CONFIRM_MS = 7_000L

    private fun handleDetectedTitle(title: String) {
        val now = System.currentTimeMillis()
        recentTitleChangeTimestamps.add(now)
        recentTitleChangeTimestamps.removeAll { now - it > BURST_WINDOW_MS }

        if (recentTitleChangeTimestamps.size >= BURST_THRESHOLD) {
            // Several videos changed within the last 45 seconds - treat as a
            // Shorts-scrolling burst, log ONE distraction entry for it rather
            // than chasing each individual video. No confirmation delay
            // needed here - the burst pattern itself IS the confirmation.
            pendingRunnable?.let { handler.removeCallbacks(it) }
            pendingTitle = null
            handleNewTitle(SHORTS_BURST_TITLE, forceType = "DISTRACTION")
        } else {
            // Possible single video - or possible feed-scroll preview
            // flicker. Cancel any earlier pending confirmation (that title
            // clearly wasn't stable, since THIS new title just replaced it)
            // and wait to see if THIS one sticks around.
            pendingRunnable?.let { handler.removeCallbacks(it) }
            pendingTitle = title
            val runnable = Runnable {
                if (pendingTitle == title) handleNewTitle(title)
            }
            pendingRunnable = runnable
            handler.postDelayed(runnable, MIN_WATCH_CONFIRM_MS)
        }
    }

    private var activeYoutubeController: MediaController? = null

    private val mediaControllerCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
            if (!title.isNullOrBlank()) handleDetectedTitle(title)
        }
    }

    private val activeSessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
        attachToYoutubeSession(controllers)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val self = ComponentName(this, DhyaanNotificationListener::class.java)
            msm.addOnActiveSessionsChangedListener(activeSessionsListener, self)
            // Catch a video that was already playing before we connected.
            attachToYoutubeSession(msm.getActiveSessions(self))
        } catch (e: Exception) {
            // If this fails for any reason, notification-based detection
            // (onNotificationPosted below) still works as a fallback.
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            msm.removeOnActiveSessionsChangedListener(activeSessionsListener)
        } catch (e: Exception) {
            // ignore
        }
        activeYoutubeController?.unregisterCallback(mediaControllerCallback)
        activeYoutubeController = null
        pendingRunnable?.let { handler.removeCallbacks(it) }
        pendingRunnable = null
        pendingTitle = null
    }

    private fun attachToYoutubeSession(controllers: List<MediaController>?) {
        val ytController = controllers?.find { it.packageName == YOUTUBE_PACKAGE }
        // Only re-attach if this is actually a different session than the one
        // we're already watching, to avoid pointlessly unregister/re-registering.
        if (ytController?.sessionToken == activeYoutubeController?.sessionToken) return

        activeYoutubeController?.unregisterCallback(mediaControllerCallback)
        activeYoutubeController = ytController
        activeYoutubeController?.registerCallback(mediaControllerCallback)

        // Check whatever's already playing right now on this session too -
        // onMetadataChanged only fires on the NEXT change, so without this,
        // a video already playing when we attach would be missed until the
        // student switches to a different video.
        val title = activeYoutubeController?.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
        if (!title.isNullOrBlank()) handleDetectedTitle(title)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null || sbn.packageName != YOUTUBE_PACKAGE) return

        try {
            val title = sbn.notification.extras.getCharSequence("android.title")?.toString()
            if (title.isNullOrBlank()) return
            handleDetectedTitle(title)
        } catch (e: Exception) {
            // ignore malformed notifications
        }
    }

    private fun handleNewTitle(title: String, forceType: String? = null) {
        val prefs = DhyaanCore.prefs(this)
        val lastTitle = prefs.getString(DhyaanCore.PREFIX + "last_processed_title", null)
        val lastMs = prefs.getLong(DhyaanCore.PREFIX + "last_processed_title_ms", 0L)
        val nowMs = System.currentTimeMillis()

        // De-dupe: skip if the same title was already processed within the last 5 minutes.
        // (This same check is what naturally stops the Shorts-burst entry below from
        // spamming - it always uses the same synthetic title, so repeat bursts within
        // 5 minutes just fold into "already logged," no separate cooldown needed.)
        if (title == lastTitle && (nowMs - lastMs) < DEDUPE_WINDOW_MS) return

        val type = forceType ?: TitleTagger.tag(title)
        val timeStr = SimpleDateFormat("hh:mm a", Locale.US).format(Date(nowMs))
        val entry = "$title|||$timeStr|||$type"

        // Update the local history Dart reads for the Student Dashboard's
        // own display. IMPORTANT: this is stored as a single plain string
        // with entries separated by "\n" - NOT via the Flutter
        // shared_preferences plugin's List<String> type. That plugin
        // encodes lists in its own internal format that's version-specific
        // and not meant to be replicated from native code, so both this
        // native writer and the Dart reader use plain getString/setString
        // on this key and split/join the delimiter themselves instead.
        val existingRaw = prefs.getString(DhyaanCore.PREFIX + "yt_history_raw", "") ?: ""
        val history = if (existingRaw.isBlank()) mutableListOf() else existingRaw.split("\n").toMutableList()
        history.add(0, entry)
        while (history.size > MAX_LOCAL_HISTORY) history.removeAt(history.size - 1)

        prefs.edit()
            .putString(DhyaanCore.PREFIX + "yt_history_raw", history.joinToString("\n"))
            .putString(DhyaanCore.PREFIX + "last_processed_title", title)
            .putLong(DhyaanCore.PREFIX + "last_processed_title_ms", nowMs)
            .apply()

        val studentDoc = DhyaanCore.studentDoc(this) ?: return
        val histRef = studentDoc.collection("history").document(nowMs.toString())
        histRef.set(
            mapOf(
                "title" to title,
                "time" to timeStr,
                "type" to type,
                "createdAt" to Timestamp.now()
            )
        )
        studentDoc.set(mapOf("historyCount" to FieldValue.increment(1)), SetOptions.merge())

        // Same cheap-pruning approach as before: only check every N writes,
        // using the atomic counter (no read needed to increment it), and
        // only ever read/delete the exact overflow amount - never the whole
        // collection. See README "Multi-user support & scale" for why this
        // matters at real scale.
        val writesSince = prefs.getInt(DhyaanCore.PREFIX + "writes_since_prune", 0) + 1
        if (writesSince >= PRUNE_EVERY_N_WRITES) {
            prefs.edit().putInt(DhyaanCore.PREFIX + "writes_since_prune", 0).apply()
            studentDoc.get().addOnSuccessListener { snap ->
                val count = (snap.getLong("historyCount") ?: 0L).toInt()
                if (count > 100) {
                    val overflow = count - 100
                    studentDoc.collection("history")
                        .orderBy("createdAt", com.google.firebase.firestore.Query.Direction.ASCENDING)
                        .limit(overflow.toLong())
                        .get()
                        .addOnSuccessListener { oldQuery ->
                            if (!oldQuery.isEmpty) {
                                val batch = com.google.firebase.firestore.FirebaseFirestore.getInstance().batch()
                                for (d in oldQuery.documents) batch.delete(d.reference)
                                batch.set(
                                    studentDoc,
                                    mapOf("historyCount" to FieldValue.increment(-oldQuery.size().toLong())),
                                    SetOptions.merge()
                                )
                                batch.commit()
                            }
                        }
                }
            }
        } else {
            prefs.edit().putInt(DhyaanCore.PREFIX + "writes_since_prune", writesSince).apply()
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        // no-op
    }
}
