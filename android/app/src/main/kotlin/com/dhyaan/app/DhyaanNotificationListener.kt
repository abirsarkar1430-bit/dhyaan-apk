package com.dhyaan.app

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Listens for system notifications and extracts the title of whatever video
 * YouTube is currently playing (YouTube posts a media-style notification
 * with the video title while a video plays). Everything - de-duping,
 * tagging STUDY/DISTRACTION, saving to Firestore, keeping the local history
 * list, pruning old entries - now happens RIGHT HERE, natively, the moment
 * the title is detected. This used to be split out to Dart code that polled
 * every few seconds, but that only worked while the Dhyaan app screen was
 * alive - which it normally won't be while a student is actually studying.
 *
 * Only YouTube's own notification is read, and only its title field - no
 * other app's notifications are inspected or stored.
 */
class DhyaanNotificationListener : NotificationListenerService() {

    private val YOUTUBE_PACKAGE = "com.google.android.youtube"
    private val MAX_LOCAL_HISTORY = 40
    private val DEDUPE_WINDOW_MS = 5 * 60 * 1000L
    private val PRUNE_EVERY_N_WRITES = 5

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null || sbn.packageName != YOUTUBE_PACKAGE) return

        try {
            val title = sbn.notification.extras.getCharSequence("android.title")?.toString()
            if (title.isNullOrBlank()) return
            handleNewTitle(title)
        } catch (e: Exception) {
            // ignore malformed notifications
        }
    }

    private fun handleNewTitle(title: String) {
        val prefs = DhyaanCore.prefs(this)
        val lastTitle = prefs.getString(DhyaanCore.PREFIX + "last_processed_title", null)
        val lastMs = prefs.getLong(DhyaanCore.PREFIX + "last_processed_title_ms", 0L)
        val nowMs = System.currentTimeMillis()

        // De-dupe: skip if the same title was already processed within the last 5 minutes.
        if (title == lastTitle && (nowMs - lastMs) < DEDUPE_WINDOW_MS) return

        val type = TitleTagger.tag(title)
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
