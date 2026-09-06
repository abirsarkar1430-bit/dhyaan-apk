package com.dhyaan.app

import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.SharedPreferences
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Everything here runs natively (no Dart/Flutter needed), because a real
 * student closes the Dhyaan app - or swipes it from recents entirely -
 * right after tapping "Start Studying." Only the foreground service and
 * this kind of plain background code keep running at that point; the
 * Flutter screen and anything that only lived inside it does not.
 *
 * All reads/writes use the SAME SharedPreferences file + key prefix as the
 * shared_preferences Flutter plugin ("FlutterSharedPreferences", keys
 * prefixed "flutter."), so whatever runs here stays in sync with whatever
 * the Dart UI shows whenever the student does happen to open the app.
 */
object DhyaanCore {
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val PREFIX = "flutter."

    fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun studentEmail(context: Context): String? {
        val e = prefs(context).getString(PREFIX + "student_email", null)
        return if (e.isNullOrBlank()) null else e
    }

    fun studentDoc(context: Context) =
        studentEmail(context)?.let { FirebaseFirestore.getInstance().collection("students").doc(it) }

    // ------------------------------------------------------------------
    // Weekly rollover ("This Week - Studied/Distracted" reset every Monday)
    // ------------------------------------------------------------------

    fun mondayOfWeek(date: Date = Date()): String {
        val cal = Calendar.getInstance()
        cal.time = date
        cal.firstDayOfWeek = Calendar.MONDAY
        // Roll back to the Monday of this week
        val diff = (cal.get(Calendar.DAY_OF_WEEK) - Calendar.MONDAY + 7) % 7
        cal.add(Calendar.DAY_OF_MONTH, -diff)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)
    }

    /**
     * Checks whether the stored week has changed since we last looked; if
     * so, resets both weekly counters to 0 (locally and in Firestore)
     * before any new time gets added. Call this before crediting either
     * weekly counter.
     */
    fun ensureCurrentWeek(context: Context) {
        val p = prefs(context)
        val currentMonday = mondayOfWeek()
        val storedMonday = p.getString(PREFIX + "week_start_date", null)
        if (storedMonday != currentMonday) {
            p.edit()
                .putString(PREFIX + "week_start_date", currentMonday)
                .putLong(PREFIX + "week_study_ms", 0L)
                .putLong(PREFIX + "week_distraction_ms", 0L)
                .apply()
            studentDoc(context)?.set(
                mapOf(
                    "weekStartDate" to currentMonday,
                    "weekStudyMins" to 0,
                    "weekDistractionMins" to 0
                ),
                SetOptions.merge()
            )
        }
    }

    fun creditWeeklyStudyMs(context: Context, addMs: Long) {
        ensureCurrentWeek(context)
        val p = prefs(context)
        val newMs = p.getLong(PREFIX + "week_study_ms", 0L) + addMs
        p.edit().putLong(PREFIX + "week_study_ms", newMs).apply()
        studentDoc(context)?.set(
            mapOf("weekStudyMins" to (newMs / 60000L).toInt()),
            SetOptions.merge()
        )
    }

    fun creditWeeklyDistractionMs(context: Context, addMs: Long) {
        if (addMs <= 0) return
        ensureCurrentWeek(context)
        val p = prefs(context)
        val newMs = p.getLong(PREFIX + "week_distraction_ms", 0L) + addMs
        p.edit().putLong(PREFIX + "week_distraction_ms", newMs).apply()
        studentDoc(context)?.set(
            mapOf("weekDistractionMins" to (newMs / 60000L).toInt()),
            SetOptions.merge()
        )
    }

    // ------------------------------------------------------------------
    // App usage (UsageStatsManager) - shared by MainActivity (for the
    // Dart "All Apps Usage Today" card) and StudyForegroundService (for
    // "apps used during this study session").
    // ------------------------------------------------------------------

    /** Package -> minutes used since midnight today. */
    fun getAllAppsUsageMinutesToday(context: Context): HashMap<String, Long> {
        val usageMap = HashMap<String, Long>()
        try {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
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
}

/**
 * YouTube title tagging - single source of truth (previously duplicated in
 * Dart, which caused a real risk of double-processing; now this native
 * copy is the only one that actually writes to Firestore).
 *
 * Format overrides content: Reels/Shorts are ALWAYS distraction, checked
 * before subject-matter keywords, so a "Physics Reel" still counts as a
 * distraction - the scroll-driven short-form format is the problem, not
 * necessarily the topic.
 */
object TitleTagger {

    private val FORMAT_OVERRIDE_DISTRACTION = listOf(
        "reel", "reels", "#reel", "#reels", "#shorts", "shorts", "short video"
    )

    private val STUDY_KEYWORDS = listOf(
        "physics", "chemistry", "maths", "mathematics", "biology", "ncert", "cbse",
        "icse", "neet", "jee", "jee main", "jee advanced", "upsc", "boards",
        "board exam", "class 12", "class 11", "class 10", "class 9", "class 8",
        "lecture", "one shot", "oneshot", "pyq", "previous year", "previous year question",
        "formula", "formula sheet", "trick", "shortcut trick", "derivation",
        "numericals", "numerical problems", "solved examples", "exercise solution",
        "electrostatics", "current electricity", "optics", "ray optics", "wave optics",
        "thermodynamics", "kinematics", "laws of motion", "work energy power",
        "gravitation", "rotational motion", "oscillations", "shm", "waves",
        "electromagnetic induction", "magnetism", "semiconductors", "nuclear physics",
        "modern physics", "dual nature of matter", "communication systems",
        "chemical bonding", "organic chemistry", "inorganic chemistry",
        "physical chemistry", "periodic table", "periodic properties",
        "mole concept", "stoichiometry", "equilibrium", "electrochemistry",
        "thermochemistry", "chemical kinetics", "surface chemistry", "polymers",
        "biomolecules", "coordination compounds", "p block", "s block", "d block",
        "alcohols phenols ethers", "aldehydes ketones", "amines", "hydrocarbons",
        "redox reactions", "calculus", "integration", "differentiation",
        "limits continuity", "vectors", "vector algebra", "3d geometry", "matrices",
        "determinants", "probability", "permutation combination", "trigonometry",
        "algebra", "sequences and series", "complex numbers", "quadratic equations",
        "straight lines", "circles", "conic sections", "differential equations",
        "statistics maths", "genetics", "cell biology", "human physiology",
        "plant physiology", "ecology", "evolution", "reproduction", "biotechnology",
        "botany", "zoology", "anatomy", "molecular biology", "revision",
        "crash course", "quick revision", "concept clarity", "chapter wise",
        "topic wise", "important questions", "sample paper", "mock test",
        "test series", "doubt clearing", "doubt session", "live class",
        "study with me", "exam strategy", "preparation tips", "time table",
        "study plan", "toppers talk", "rank booster", "ncert solutions",
        "ncert exemplar", "jee mains", "neet 2026", "gate exam", "ssc cgl",
        "ssc chsl", "bank po", "railway exam", "competitive exam",
        "entrance exam", "syllabus", "exam pattern", "answer key",
        "cut off marks", "general knowledge", "current affairs",
        "english grammar", "reasoning ability", "quantitative aptitude",
        "coding class", "programming tutorial", "python tutorial",
        "java tutorial", "dsa", "data structures algorithms", "computer science",
        "economics class", "history class", "geography class", "polity", "civics"
    )

    private val DISTRACTION_KEYWORDS = listOf(
        "roast", "funny", "meme", "memes", "comedy", "bgmi", "pubg", "free fire",
        "valorant", "call of duty", "bigg boss", "reels", "shorts", "vlog",
        "prank", "reaction", "movie trailer", "song", "music video", "dance",
        "gaming", "gameplay", "let's play", "stream highlights", "twitch",
        "stand up comedy", "sketch comedy", "troll", "savage reply", "clapback",
        "fight compilation", "cringe", "funny moments", "best moments compilation",
        "wwe highlights", "football highlights", "cricket highlights",
        "ipl highlights", "match highlights", "live match", "love story",
        "romantic scene", "movie scene", "movie clip", "full movie", "web series",
        "netflix", "ott release", "trailer reaction", "unboxing", "haul video",
        "get ready with me", "grwm", "makeup tutorial", "fashion lookbook",
        "lifestyle vlog", "day in my life", "couple vlog", "travel vlog",
        "food vlog", "mukbang", "asmr", "satisfying video", "oddly satisfying",
        "viral video", "trending video", "trending reel", "tiktok compilation",
        "instagram reel", "status video", "whatsapp status", "love song",
        "sad song", "breakup song", "party song", "item song", "remix song",
        "dj remix", "lofi mix", "gaming montage", "headshot montage",
        "funny gaming moments", "stand up special", "roast video",
        "celebrity gossip", "bollywood news", "gossip news",
        "entertainment news", "award show", "reality show", "dating show",
        "crime patrol", "horror story", "scary story", "ghost story",
        "prank call", "clash of clans", "clash royale", "minecraft gameplay",
        "gta gameplay", "among us funny", "fortnite gameplay",
        "youtube shorts", "shorts compilation", "funny shorts", "meme review",
        "stand up clip", "talk show clip", "chat show", "podcast clip funny",
        "celebrity interview", "fan moment", "concert video", "live concert",
        "singing competition", "dance competition", "reality tv clip",
        "wedding video", "sangeet dance", "birthday party video",
        "new movie song", "trailer launch", "teaser release", "first look poster",
        "box office", "movie review funny", "song status", "lyrical video",
        "dj song", "party mix", "club music", "edm mix", "bollywood dance",
        "kids cartoon", "cartoon funny", "animation comedy", "comedy skit",
        "youtube prank", "funny fails", "fail compilation", "epic fails",
        "satisfying compilation", "asmr eating"
    )

    fun tag(rawTitle: String): String {
        val title = rawTitle.lowercase(Locale.US)
        for (kw in FORMAT_OVERRIDE_DISTRACTION) if (title.contains(kw)) return "DISTRACTION"
        for (kw in STUDY_KEYWORDS) if (title.contains(kw)) return "STUDY"
        for (kw in DISTRACTION_KEYWORDS) if (title.contains(kw)) return "DISTRACTION"
        return "DISTRACTION"
    }
}
