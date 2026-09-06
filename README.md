# Dhyaan - Padhai ka Sach

Study-accountability app: student tracks their own study sessions (with a
visible, ongoing "tracking" notification — never hidden), and a parent on a
different phone can see progress in real time via Firestore. Built for the
Firebase Spark (free) plan, targeting ~100 users.

## ⚠️ One-time setup step before your first build

This zip contains all the **source** you asked for (Dart, Kotlin, Gradle
config, manifest, CI workflow, Firestore rules). What it can *not* contain is
the Gradle **wrapper binary** (`gradle-wrapper.jar`) — that's a compiled
binary file that only the Flutter/Gradle tooling can generate, and this
build environment has no internet access to Gradle's or Flutter's servers to
fetch one for you.

**Fix (takes 30 seconds, one time only):**

1. Install Flutter 3.22.2 locally if you don't have it: https://docs.flutter.dev/get-started/install
2. Unzip this project, `cd` into it, then run:
   ```bash
   flutter create --platforms=android .
   ```
   This regenerates the missing `android/gradlew`, `gradlew.bat`, and
   `gradle/wrapper/gradle-wrapper.jar` files **without touching** any of the
   Dart/Kotlin/manifest files already in this zip (it only fills in what's
   missing).
3. Commit the whole folder to a GitHub repo. The included
   `.github/workflows/build_apk.yml` will then build a debug-signed release
   APK on every push to `main`, downloadable from the Actions tab.

If you'd rather skip GitHub Actions entirely, just run locally:
```bash
flutter pub get
flutter build apk --release
```
The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

## Firebase setup (put your real file here)

Replace the placeholder at:
```
android/app/google-services.json
```
with your real file downloaded from Firebase Console → Project Settings →
Your apps → Android app (package name **must** be `com.dhyaan.app`).

Then deploy the included Firestore rules/indexes (optional but recommended,
`firebase-tools` required):
```bash
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules,firestore:indexes
```

## What's implemented

- **Role select** → Student / Parent, premium light theme (`#F8FAFC` bg,
  white cards, `#E2E8F0` border, 18px radius, black primary buttons, green
  `#10B981` = study, red `#EF4444` = distraction).
- **Student login**: name/email/phone → looks up (or creates) a permanent
  6-digit code in `students/{email}`. Code never regenerates on re-login.
- **Student dashboard**:
  - Permission banner for Usage Access + Notification Access, with buttons
    that open the correct system settings screens.
  - Start/Stop Studying — starts a real **foreground service**
    (`StudyForegroundService.kt`) with an ongoing notification showing a
    live `hh:mm:ss` timer, survives the app being swiped from recents.
  - Offline Study card — implemented via a `WidgetsBindingObserver` in
    `main.dart` that mirrors the exact onPause/onResume spec (save
    `last_pause_ms` on pause; on resume, if the gap is 5 min–4 hr, add it to
    `offline_study_ms` locally and sync to Firestore).
  - All Apps Usage Today — via `UsageStatsManager` (native, `MainActivity.kt`),
    top 6 apps ≥1 minute, with Refresh.
  - YouTube Titles — `DhyaanNotificationListener.kt` grabs the title from
    YouTube's own playback notification only (no other app's notifications
    are read or stored) and writes it to shared prefs; Dart polls every 3s,
    de-dupes same-title-within-5-minutes, tags STUDY/DISTRACTION against
    100+ keyword lists each, saves to local history (capped at 40) and to
    Firestore `students/{email}/history/{id}` (auto-pruned to the most
    recent 100 docs per student to stay inside the Spark free tier).
  - Clear button wipes local + Firestore history. Preview buttons show a
    demo tag without saving anything. Empty states say "No titles yet."
- **Parent login (different phone)**: enter child's email + code, verified
  directly against the `students/{email}` doc.
- **Parent dashboard**: fully realtime via `StreamBuilder`/Firestore
  snapshots — linked code/email, offline/total minutes, study vs. distraction
  counts, a weekly-focus bar chart, and three live-updating lists (Studied
  Today / Distractions Detected / Full YouTube History).

## Multi-user support & scale

Yes — the data model is per-student (`students/{email}`), so 100 different
students never collide, each with their own code, history, and linked
parent(s). The tracking itself (foreground service, notification listener)
runs entirely on each student's own phone, so there's no shared/contended
state between users either.

One real scaling risk worth knowing about: the "keep only last 100 titles"
cleanup used to run a full Firestore read of a student's entire history
subcollection on **every single new YouTube title** — for an active student
that scaled directly with how much they watched (a 100-video/day student
could cost 1,000+ reads/day on this check alone, which adds up fast across
many users). This is now fixed properly: an atomic counter
(`FieldValue.increment`, a write, not a read) tracks the count with zero
read cost, and the periodic cleanup only ever reads one small student doc
plus a tightly-bounded query for exactly the docs being deleted - so the
cost per user stays flat and tiny no matter how active they are.

Also: **Reels/Shorts are now always tagged DISTRACTION**, regardless of
subject-matter keywords in the title. A "NEET Physics Tricks" video as a
Reel is still checked *before* the study-keyword match, since the
short-form, scroll-driven format itself is the distraction — not
necessarily the topic.

Two things NOT covered, since they're security/abuse concerns rather than
"will it technically run" concerns — worth doing before a wide public launch:
- Firestore rules are open (`allow read, write: if true`) — fine for ~100
  known users you trust, but anyone with your project ID could read/write
  any student's data if this app were ever made public.
- There's no rate limiting on Firestore writes from the client, so a buggy
  or malicious client could in theory spam writes past the free quota for
  everyone. Not a concern at pilot scale; worth revisiting before scaling
  past a small trusted group.

## Weekly totals (new)

Both dashboards now show **"This Week - Studied"** and **"This Week -
Distracted"**, which automatically reset to zero every Monday - exactly as
requested, no manual action needed. Under the hood: a `weekStartDate` field
on the student doc tracks which week is currently being counted; the app
checks this on every relevant update, and if the calendar has rolled into a
new week since the last check, it resets both counters before adding
anything new.

- **"Studied"** = the existing offline-study signal (screen off while a
  study session is active), summed for the current week.
- **"Distracted"** = total time spent actively using apps today, summed for
  the current week. Since Android reports this as a running daily total
  (not an incremental amount), the app tracks how much of today's total has
  already been counted and only adds the difference each time - otherwise
  the same minutes would get added again every refresh.

**Known limitation, flagged honestly:** this gives you one accurate number
for "the whole week so far," but not a day-by-day breakdown. The "WEEKLY
FOCUS" bar chart on the parent dashboard is still the illustrative static
data mentioned earlier - building a real per-day trend chart would need the
app to save a small snapshot once every day (not built yet, but a natural
next step if you want that view later).

## Major architecture change: tracking now survives the app being closed

**The problem this fixes:** almost all of the "smart" tracking logic
(crediting offline study time, tagging YouTube titles, weekly totals) used
to live inside the Dhyaan app's own screen, and only ran while that screen
was alive in memory. In real use, a student taps "Start Studying" and then
closes the app - sometimes clearing it from recents entirely. Everything
that depended on the screen staying open would have silently stopped
working at exactly that point. This has been restructured so the actual
work happens in the background service instead, which is the one thing
guaranteed to keep running:

- **Real screen on/off detection** (`StudyForegroundService.kt`, via a
  `BroadcastReceiver` for Android's own `ACTION_SCREEN_ON`/`ACTION_SCREEN_OFF`)
  now drives "offline study" crediting - accurately distinguishing "the
  screen actually turned off" from "the student switched to a different app
  while the screen stayed on" (the gap flagged earlier - now fixed).
- **YouTube title detection, tagging, de-duping, and saving to Firestore**
  now all happen the instant a title is detected
  (`DhyaanNotificationListener.kt`), natively - no more waiting on the
  Flutter app to poll for it. The STUDY/DISTRACTION keyword lists (and the
  Reels-always-distraction rule) now live in one place,
  `TitleTagger` inside `DhyaanCore.kt`, so there's a single source of truth
  instead of a Dart copy and a Kotlin copy that could drift out of sync.
- **Weekly totals** are credited directly from the background service to
  Firestore, so "This Week" keeps updating even if the student never
  reopens the app between sessions.
- Flutter/Dart is now purely a **display layer**: it reads whatever the
  background service has already written (from local prefs for instant
  numbers, and Firestore for realtime parent viewing) - it doesn't do any
  of the actual detection or crediting itself anymore.

## New: "During Last Study Session" app breakdown

At the moment a session starts, the app takes a snapshot of every app's
usage-so-far; when the session ends (or every 5 minutes during a long
session), it compares against that snapshot to work out exactly which apps
were used, and for how long, **while studying was supposedly happening**.
This is shown on both the student's and parent's dashboard as "During Last
Study Session" - per-student, time-only (which app, how many minutes) -
**never video titles or content**, matching exactly what you asked for on
the institute-privacy question earlier: time visibility without content
visibility. This same per-app time data also feeds the weekly "Distracted"
number, which is now specifically "time spent on apps while a study
session was active," not generic all-day phone usage - a more meaningful
number for exactly the reason you raised it (institutes wanting to see
distraction during claimed study time).

**Known limitation, flagged honestly:** app names currently show as their
raw Android package name (e.g. `com.instagram.android`) rather than a
friendly name like "Instagram." Mapping that requires either a small
lookup table or reading it from the device's app list - not built yet,
easy to add later if it matters for how this looks to parents/institutes.

## ⚠️ This is the highest-risk part of the whole build - please test it deliberately

This was a substantial rewrite of how the app's core tracking works, done
by hand without the ability to compile or run it in the environment that
produced this zip (no Flutter/Android toolchain available there - see the
very first section of this README). Everything was written as carefully
and correctly as possible, including fixing a couple of real bugs caught
along the way (an Android API that doesn't actually exist as I'd first
written it, a date-formatting call that would have crashed at runtime, and
a newer-Android registration requirement that would have crashed on
Android 13+ devices) - but this is exactly the kind of change that
deserves real on-device testing before you trust the numbers, especially
before showing them to a paying institute. A concrete test plan:

1. Grant Usage Access and Notification Access (the two permission banner buttons).
2. Tap **Start Studying**, then **fully close the app and clear it from
   recents.** Lock the phone (screen off) for a few minutes, then unlock it.
   Reopen Dhyaan - "Offline Study" and "This Week - Studied" should have
   increased.
3. With the app still closed, play a video on YouTube with an obviously
   study-sounding title (e.g. "NEET Physics Revision"). Check back in
   Dhyaan (or on the parent's linked device) - it should appear tagged
   STUDY within a few seconds, without you ever reopening Dhyaan.
4. Try a title with "Reel" or "Short" in it, even with study keywords -
   confirm it's tagged DISTRACTION.
5. While a session is active, use a different app (e.g. Instagram) for a
   few minutes with the screen on, then tap **Stop**. Check "During Last
   Study Session" on both dashboards - that app and roughly that many
   minutes should appear.
6. Let a session run past a 5-minute mark of the app being open, confirm
   the notification's timer is still counting correctly, and Stop works
   from the notification's own "Stop" button as well as the in-app one.

If any of these don't behave as described, that's the first place to look -
and exactly the kind of thing worth telling me so it can get fixed before
this goes further.

**One more forward-looking note, not urgent right now:** Android 14
(API 34) puts stricter limits on how long certain foreground service types
can run continuously. This app's service type (`dataSync`) should be fine
for typical study session lengths, but if you start seeing very long
sessions (many hours) get cut off unexpectedly on newer phones, that's the
likely cause, and there's a different service-type configuration for that
case if it comes up.

## Known simplifications (flagged honestly, not hidden)

- **Weekly Focus chart** uses the exact static demo values from the spec
  (`M 3.2 T 2.1 W 4.5 T 3.8 F 2.9 S 5.1`) since no real per-day aggregation
  source was defined — it's cosmetic. Wire it to a real `dailyMinutes` map
  in Firestore if you want it live.
- **App icon** is a simple generated placeholder (dark square + green dot),
  not a designed logo — swap the PNGs in `android/app/src/main/res/mipmap-*`
  whenever you have real branding.
- **Signing**: release builds use the Flutter debug keystore so CI "just
  works" for free. Fine for personal/testing use; add your own keystore +
  `signingConfig` in `android/app/build.gradle` before any public release.
- **Firestore rules** are wide open (`allow read, write: if true`) to avoid
  needing Firebase Auth for an MVP — anyone with your project ID can read/
  write. Acceptable for a small private pilot; tighten before wider release.
- I could not actually run `flutter build apk` in the environment that
  produced this zip (no Flutter SDK / no internet to Gradle's servers there),
  so while every file was hand-written and cross-checked, treat the very
  first build as "the thing that surfaces any typo," and paste me the exact
  error if one comes up.

## Project structure

```
lib/main.dart                                          - entire app UI + logic
android/app/src/main/kotlin/com/dhyaan/app/
  MainActivity.kt                                       - MethodChannel + UsageStatsManager
  StudyForegroundService.kt                              - ongoing study notification
  DhyaanNotificationListener.kt                          - YouTube title capture
android/app/src/main/AndroidManifest.xml
android/app/build.gradle
android/build.gradle / settings.gradle / gradle.properties
android/app/google-services.json                        - PLACEHOLDER, replace me
firestore.rules / firestore.indexes.json
firebase.json
.github/workflows/build_apk.yml
```
