import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// COLORS / THEME
// ============================================================================
const kBg = Color(0xFFF8FAFC);
const kCardBorder = Color(0xFFE2E8F0);
const kBlack = Color(0xFF0F172A);
const kGreen = Color(0xFF10B981);
const kRed = Color(0xFFEF4444);
const kMuted = Color(0xFF64748B);
const kRadius = 18.0;

// ============================================================================
// METHOD CHANNEL
// ============================================================================
class NativeBridge {
  static const _channel = MethodChannel('com.dhyaan.app/usage');

  static Future<Map<String, int>> getAllAppsUsage() async {
    try {
      final result = await _channel.invokeMethod('getAllAppsUsage');
      if (result == null) return {};
      final map = Map<String, dynamic>.from(result as Map);
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<int> getYoutubeUsage() async {
    try {
      final result = await _channel.invokeMethod('getYoutubeUsage');
      return (result as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> getOfflineStudyTime() async {
    try {
      final result = await _channel.invokeMethod('getOfflineStudyTime');
      return (result as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> hasUsagePermission() async {
    try {
      final result = await _channel.invokeMethod('hasUsagePermission');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasNotifPermission() async {
    try {
      final result = await _channel.invokeMethod('hasNotifPermission');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUsageSettings() async {
    try {
      await _channel.invokeMethod('openUsageSettings');
    } catch (_) {}
  }

  static Future<void> openNotifSettings() async {
    try {
      await _channel.invokeMethod('openNotifSettings');
    } catch (_) {}
  }

  static Future<void> startStudyService() async {
    try {
      await _channel.invokeMethod('startStudyService');
    } catch (_) {}
  }

  static Future<void> stopStudyService() async {
    try {
      await _channel.invokeMethod('stopStudyService');
    } catch (_) {}
  }

  // Returns friendly names of known clone/dual-space apps found installed
  // (e.g. "Parallel Space"). Empty list means none of the KNOWN ones were
  // found - see CloneAppDetector.kt for why this can't cover every case
  // (phone-brand built-in dual-app features are architecturally invisible
  // to any regular app, not just this one).
  static Future<List<String>> checkCloneApps() async {
    try {
      final result = await _channel.invokeMethod('checkCloneApps');
      if (result == null) return [];
      return List<String>.from(result as List);
    } catch (_) {
      return [];
    }
  }

  static Future<String> getDeviceBrand() async {
    try {
      final result = await _channel.invokeMethod('getDeviceBrand');
      return (result as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  // POST_NOTIFICATIONS - the runtime popup required on Android 13+ or the
  // ongoing study-tracking notification silently never appears. Separate
  // from hasNotifPermission()/openNotifSettings() above, which are for a
  // completely different permission (Notification Listener access, for
  // reading YouTube's notifications) - same word "notification," different
  // Android permission entirely.
  static Future<bool> hasNotifPostPermission() async {
    try {
      final result = await _channel.invokeMethod('hasNotifPostPermission');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestNotifPostPermission() async {
    try {
      await _channel.invokeMethod('requestNotifPostPermission');
    } catch (_) {}
  }
}

// ============================================================================
// NOTE: YouTube title tagging (STUDY/DISTRACTION keyword matching) used to
// live here in Dart. It has moved entirely to native Kotlin
// (TitleTagger.kt / DhyaanCore.kt), because that logic needs to run the
// moment a new YouTube title is detected - which normally happens while a
// student has closed the Dhyaan app and is just studying with the phone
// screen off. Keeping two separate copies of the tagging logic (one in
// Dart, one in Kotlin) risked both processing the same title and writing
// duplicate Firestore entries, so this is now single-sourced natively.
// ============================================================================

// ============================================================================
// MAIN
// ============================================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  runApp(const DhyaanApp());
}

class DhyaanApp extends StatelessWidget {
  const DhyaanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dhyaan - Padhai ka Sach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBlack,
          background: kBg,
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: kBlack,
              displayColor: kBlack,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          foregroundColor: kBlack,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kBlack,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kCardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kCardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBlack, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const SessionGate(),
    );
  }
}

// ============================================================================
// SHARED UI HELPERS
// ============================================================================
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: kCardBorder),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBlack));
  }
}

Widget footer() {
  return const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text('© 2026 Dhyaan', style: TextStyle(color: kMuted, fontSize: 12)),
    ),
  );
}

String fmtMinutes(int mins) {
  if (mins < 60) return '${mins}m';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String fmtHms(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// 'yyyy-MM-dd' key matching the native side's SimpleDateFormat("yyyy-MM-dd")
// used for daily stats document IDs. Written by hand rather than pulling in
// the intl package just for this one format.
String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ============================================================================
// FRIENDLY APP NAMES
// Android restricts querying "what's every app on this phone called" since
// Android 11 (the QUERY_ALL_PACKAGES permission) - and Google Play scrutinizes
// that permission heavily, which isn't worth the risk for a monitoring-category
// app that already gets extra review attention. Instead: a lookup table of
// ~35 well-known apps students commonly use. Anything not in this list just
// shows its raw package name (e.g. "com.some.obscure.app") rather than a
// guessed-and-possibly-wrong friendly name - a correct technical name beats
// a confident-looking wrong one.
// ============================================================================
const Map<String, String> kFriendlyAppNames = {
  // Social / messaging
  'com.whatsapp': 'WhatsApp',
  'com.instagram.android': 'Instagram',
  'com.facebook.katana': 'Facebook',
  'com.facebook.orca': 'Messenger',
  'com.snapchat.android': 'Snapchat',
  'org.telegram.messenger': 'Telegram',
  'com.twitter.android': 'X (Twitter)',
  'com.discord': 'Discord',
  'com.zhiliaoapp.musically': 'TikTok',
  'com.linkedin.android': 'LinkedIn',
  'com.pinterest': 'Pinterest',
  'com.reddit.frontpage': 'Reddit',
  // Google apps
  'com.google.android.youtube': 'YouTube',
  'com.android.chrome': 'Chrome',
  'com.google.android.gm': 'Gmail',
  'com.google.android.apps.maps': 'Google Maps',
  'com.google.android.googlequicksearchbox': 'Google App',
  'com.google.android.apps.docs': 'Google Drive',
  'com.android.vending': 'Google Play Store',
  'com.google.android.apps.youtube.music': 'YouTube Music',
  'com.google.android.calendar': 'Google Calendar',
  'com.google.android.keep': 'Google Keep',
  // Entertainment / streaming
  'com.netflix.mediaclient': 'Netflix',
  'com.spotify.music': 'Spotify',
  'in.startv.hotstar': 'Disney+ Hotstar',
  'com.amazon.avod.thirdpartyclient': 'Prime Video',
  'com.jio.jioplay.tv': 'JioTV',
  // Gaming
  'com.pubg.imobile': 'BGMI',
  'com.dts.freefireth': 'Free Fire',
  'com.supercell.clashofclans': 'Clash of Clans',
  'com.supercell.clashroyale': 'Clash Royale',
  'com.king.candycrushsaga': 'Candy Crush Saga',
  'com.roblox.client': 'Roblox',
  'com.mojang.minecraftpe': 'Minecraft',
  // Other common apps
  'com.ubercab': 'Uber',
  'in.amazon.mShop.android.shopping': 'Amazon Shopping',
  'com.flipkart.android': 'Flipkart',
  'net.one97.paytm': 'Paytm',
  'com.phonepe.app': 'PhonePe',
  // Educational apps (also in the "okay" / not-distraction allowlist natively)
  'org.khanacademy.android': 'Khan Academy',
  'xyz.penpencil.physicswala': 'Physics Wallah',
  'com.curiousjr': 'CuriousJr',
  'com.vedantu.app': 'Vedantu',
  'com.unacademyapp': 'Unacademy',
  'com.adobe.reader': 'Adobe Acrobat Reader',
  'com.xodo.pdf.reader': 'Xodo PDF Reader',
};

/// Returns the friendly name for a known app package, or the raw package
/// name unchanged if it's not in the list - never a guessed name.
String friendlyAppName(String packageName) => kFriendlyAppNames[packageName] ?? packageName;

// ============================================================================
// BRAND-AWARE DUAL-APP GUIDANCE
// We can't see INTO a phone brand's built-in dual-app space (that's a real
// OS-level wall, not a gap we can code around - see CloneAppDetector.kt).
// What we CAN do is tell the parent/student exactly what that brand calls
// the feature and roughly where to check for it themselves, instead of a
// generic "we can't see everything" shrug.
// ============================================================================
class BrandDualAppInfo {
  final String featureName;
  final String whereToCheck;
  const BrandDualAppInfo(this.featureName, this.whereToCheck);
}

BrandDualAppInfo? brandDualAppInfo(String rawBrand) {
  final b = rawBrand.toLowerCase();
  if (b.contains('xiaomi') || b.contains('redmi') || b.contains('poco')) {
    return const BrandDualAppInfo('Dual Apps', 'Settings > Apps > Dual Apps');
  }
  if (b.contains('samsung')) {
    return const BrandDualAppInfo(
        'Dual Messenger / Secure Folder',
        'Settings > Advanced features > Dual Messenger, or Settings > Security and privacy > Secure Folder');
  }
  if (b.contains('oppo')) {
    return const BrandDualAppInfo('Clone Apps', 'Settings > App management > Clone Apps (or Additional Settings > Clone Apps)');
  }
  if (b.contains('vivo')) {
    return const BrandDualAppInfo('App Clone', 'Settings > System Manager > App Clone (or More Settings > App Clone)');
  }
  if (b.contains('realme')) {
    return const BrandDualAppInfo('App Cloner', 'Settings > App Management > App Cloner');
  }
  if (b.contains('oneplus')) {
    return const BrandDualAppInfo('Parallel Apps', 'Settings > Utilities > Parallel Apps (may be under Special Features on newer models)');
  }
  if (b.contains('huawei') || b.contains('honor')) {
    return const BrandDualAppInfo('App Twin', 'Settings > Apps > App Twin');
  }
  return null; // Unknown brand, or one with no widely-known built-in dual-app feature.
}

// ============================================================================
// ROLE SELECT
// ============================================================================
// ============================================================================
// SESSION GATE
// Checked once on every app launch, before anything else. A student stays
// logged in until they explicitly log out (or the app's data gets cleared/
// reinstalled) - same for a parent. Only when neither a student nor a
// parent session is found does this fall through to Role Select.
// ============================================================================
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final studentEmail = prefs.getString('student_email');
    final studentCode = prefs.getString('student_code');
    final linkedEmail = prefs.getString('linkedEmail');
    final linkedCode = prefs.getString('linkedCode');

    if (!mounted) return;

    if ((studentEmail ?? '').isNotEmpty && (studentCode ?? '').isNotEmpty) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StudentDashboard()));
    } else if ((linkedEmail ?? '').isNotEmpty && (linkedCode ?? '').isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ParentDashboard(email: linkedEmail!, code: linkedCode!)),
      );
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoleSelectScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBg,
      body: Center(child: CircularProgressIndicator(color: kBlack)),
    );
  }
}

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Real logo mark
                      Image.asset('assets/images/dhyaan_mark.png', width: 60, height: 60),
                      const SizedBox(height: 18),
                      const Text('Dhyaan',
                          style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'serif',
                              letterSpacing: -0.5,
                              height: 1.0,
                              color: kBlack)),
                      const SizedBox(height: 6),
                      const Text('Focus, Measured.',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                              color: kMuted)),
                      const SizedBox(height: 56),
                      const Text('I am a...',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kMuted)),
                      const SizedBox(height: 14),
                      _RoleCard(
                        title: 'Student',
                        subtitle: 'Track your study sessions and stay accountable',
                        icon: Icons.school_rounded,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StudentEntryScreen()),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RoleCard(
                        title: 'Parent',
                        subtitle: 'View your child\'s study progress in real time',
                        icon: Icons.family_restroom_rounded,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ParentLoginScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              footer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _RoleCard({required this.title, required this.subtitle, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: kCardBorder),
          boxShadow: [
            BoxShadow(
              color: kBlack.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: kBlack,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: kBlack)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: kMuted, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: kMuted),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STUDENT LOGIN
// ============================================================================
// ============================================================================
// STUDENT ENTRY - choose new registration vs signing back in with a code
// ============================================================================
class StudentEntryScreen extends StatelessWidget {
  const StudentEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBlack)),
              const SizedBox(height: 4),
              const Text('New here, or already have your code?',
                  style: TextStyle(fontSize: 13, color: kMuted)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentLoginScreen()),
                  ),
                  child: const Text('New Student - Register'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentSignInScreen()),
                  ),
                  child: const Text('I Already Have a Code - Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STUDENT SIGN IN - lightweight re-login for a returning student who got
// logged out (app reinstalled, data cleared, etc). Only code + email, NOT
// the full registration form - the account already exists, this just
// re-authenticates against it.
// ============================================================================
class StudentSignInScreen extends StatefulWidget {
  const StudentSignInScreen({super.key});
  @override
  State<StudentSignInScreen> createState() => _StudentSignInScreenState();
}

class _StudentSignInScreenState extends State<StudentSignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    final email = _email.text.trim().toLowerCase();
    final code = _code.text.trim();
    if (email.isEmpty || code.isEmpty) {
      setState(() => _error = 'Please enter both fields');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(email).get();
      if (doc.exists && doc.data() != null && doc.data()!['code'].toString() == code) {
        final data = doc.data()!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('student_code', code);
        await prefs.setString('student_email', email);
        await prefs.setString('student_name', (data['name'] ?? '').toString());
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const StudentDashboard()),
          (route) => false,
        );
      } else {
        setState(() => _error = 'Invalid email or code');
      }
    } catch (e) {
      setState(() => _error = 'Could not reach Firebase: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome back',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBlack)),
              const SizedBox(height: 4),
              const Text('Enter your email and your permanent code',
                  style: TextStyle(fontSize: 13, color: kMuted)),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Your Code'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: kRed, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});
  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _continue() async {
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    final phone = _phone.text.trim();
    if (name.isEmpty || email.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docRef = FirebaseFirestore.instance.collection('students').doc(email);
      final snap = await docRef.get();
      String code;
      if (snap.exists && snap.data() != null && snap.data()!['code'] != null) {
        code = snap.data()!['code'].toString();
      } else {
        code = (100000 + Random().nextInt(900000)).toString();
        await docRef.set({
          'code': code,
          'email': email,
          'name': name,
          'phone': phone,
          'createdAt': Timestamp.now(),
          'offlineStudyMs': 0,
          'totalAppMins': 0,
        }, SetOptions(merge: true));
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('student_code', code);
      await prefs.setString('student_email', email);
      await prefs.setString('student_name', name);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => StudentCodeScreen(code: code)),
      );
    } catch (e) {
      setState(() => _error = 'Could not reach Firebase: $e. If this is your first run, check that you replaced android/app/google-services.json with your real Firebase file (see README).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Let\'s get you set up',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBlack)),
              const SizedBox(height: 4),
              const Text('Your parent will use your email + code to link',
                  style: TextStyle(fontSize: 13, color: kMuted)),
              const SizedBox(height: 24),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: kRed, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _continue,
                  child: _loading
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentCodeScreen extends StatelessWidget {
  final String code;
  const StudentCodeScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.verified_rounded, color: kGreen, size: 56),
              const SizedBox(height: 20),
              const Text('Your Permanent Code',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kBlack)),
              const SizedBox(height: 6),
              const Text('Won\'t change when switching', style: TextStyle(fontSize: 13, color: kMuted)),
              const SizedBox(height: 24),
              AppCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(code,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 6, color: kBlack)),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: kMuted),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const StudentDashboard()),
                    );
                  },
                  child: const Text('Go to Dashboard'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STUDENT DASHBOARD
// ============================================================================
class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});
  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with WidgetsBindingObserver {
  String code = '';
  String email = '';
  String name = '';

  bool hasUsagePermission = false;
  bool hasNotifPermission = false;
  bool hasNotifPostPermission = false;

  bool isStudying = false;
  int studySeconds = 0;
  Timer? _timerTicker;
  Timer? _ytPoller;
  Timer? _permPoller;

  int offlineMs = 0;
  Map<String, int> appsUsage = {};
  List<String> ytHistory = []; // "title|||time|||type"

  // Weekly totals - credited natively (see StudyForegroundService.kt), reset
  // automatically whenever a new week (Monday) starts. Dart just displays
  // whatever value is currently in prefs.
  int weekStudyMs = 0;
  int weekDistractionMs = 0;

  // "During last study session" app-usage breakdown, synced from Firestore
  // (written natively at the end of each session) for the student's own
  // visibility, matching what the parent dashboard also shows.
  Map<String, int> lastSessionAppUsage = {};
  int lastSessionDurationMins = 0;

  // Clone/dual-space app check - see CloneAppDetector.kt for exactly what
  // this can and can't see.
  List<String> cloneAppsFound = [];
  bool cloneCheckDone = false;
  String deviceBrand = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      code = prefs.getString('student_code') ?? '';
      email = prefs.getString('student_email') ?? '';
      name = prefs.getString('student_name') ?? '';
      isStudying = prefs.getBool('isStudying') ?? false;
      // studySeconds starts at 0 here and is immediately recalculated from
      // study_start_ms by _startTicker() below if a session is active -
      // there's no separately-persisted "study_seconds" value to restore.
      ytHistory = _decodeYtHistory(prefs.getString('yt_history_raw'));
      weekStudyMs = prefs.getInt('week_study_ms') ?? 0;
      weekDistractionMs = prefs.getInt('week_distraction_ms') ?? 0;
    });
    await _refreshPermissions();
    await _refreshAppsUsage();
    await _refreshOffline();
    await _refreshLastSession();
    await _checkCloneApps();
    if (isStudying) _startTicker();
    // Lightweight - just re-reads local prefs so the on-screen list updates
    // if the app happens to be open while a title comes in. The actual
    // detection, tagging, and Firestore save all happen natively now (see
    // DhyaanNotificationListener.kt), so this does no network/Firestore work.
    _ytPoller = Timer.periodic(const Duration(seconds: 3), (_) => _refreshLocalYtHistory());
    _permPoller = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPermissions());
  }

  // Logs out: stops any active study session first (logging out mid-session
  // would otherwise leave the foreground service running for nobody), then
  // clears identity so SessionGate falls through to Role Select next launch.
  // The student's account and code are untouched in Firestore - signing
  // back in with StudentSignInScreen (email + code) restores everything.
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?'),
        content: const Text('You can sign back in anytime with your email and your permanent code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (isStudying) {
      await NativeBridge.stopStudyService();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('student_code');
    await prefs.remove('student_email');
    await prefs.remove('student_name');
    await prefs.setBool('isStudying', false);

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
      (route) => false,
    );
  }

  // Checks for known clone/dual-space apps AND the device brand (so we can
  // give brand-specific guidance about built-in dual-app features we can't
  // see into) and syncs both to Firestore so the parent dashboard sees them
  // too. Installed apps and device brand don't change mid-session, so this
  // only needs to run once per app open (plus pull-to-refresh), not on a timer.
  Future<void> _checkCloneApps() async {
    final found = await NativeBridge.checkCloneApps();
    final brand = await NativeBridge.getDeviceBrand();
    if (mounted) {
      setState(() {
        cloneAppsFound = found;
        deviceBrand = brand;
        cloneCheckDone = true;
      });
    }
    if (email.isNotEmpty) {
      FirebaseFirestore.instance.collection('students').doc(email).set(
        {'cloneAppsDetected': found, 'deviceBrand': brand},
        SetOptions(merge: true),
      ).catchError((_) {});
    }
  }

  List<String> _decodeYtHistory(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw.split('\n');
  }

  Future<void> _refreshLocalYtHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = _decodeYtHistory(prefs.getString('yt_history_raw'));
    if (mounted && history.length != ytHistory.length) {
      setState(() => ytHistory = history);
    }
    // Also pick up any weekly-total changes credited natively in the
    // background since we last checked (e.g. a screen-off study chunk that
    // just got credited).
    final newWeekStudy = prefs.getInt('week_study_ms') ?? 0;
    final newWeekDistraction = prefs.getInt('week_distraction_ms') ?? 0;
    if (mounted && (newWeekStudy != weekStudyMs || newWeekDistraction != weekDistractionMs)) {
      setState(() {
        weekStudyMs = newWeekStudy;
        weekDistractionMs = newWeekDistraction;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerTicker?.cancel();
    _ytPoller?.cancel();
    _permPoller?.cancel();
    super.dispose();
  }

  // Note: offline-study detection used to live here, watching Dart's own
  // AppLifecycleState. That only fired while the Dhyaan screen itself was
  // alive, which isn't reliable - a real student starts a session and then
  // closes the app entirely. Real screen-on/off detection (and the weekly
  // crediting that depends on it) now happens natively in
  // StudyForegroundService.kt, which keeps running regardless. This
  // callback now just refreshes what's on screen when the student happens
  // to reopen the app - it doesn't credit anything itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _refreshOffline();
      await _refreshAppsUsage();
      await _refreshLocalYtHistory();
      await _refreshLastSession();
    }
  }

  Future<void> _refreshPermissions() async {
    final u = await NativeBridge.hasUsagePermission();
    final n = await NativeBridge.hasNotifPermission();
    final np = await NativeBridge.hasNotifPostPermission();
    if (!mounted) return;
    setState(() {
      hasUsagePermission = u;
      hasNotifPermission = n;
      hasNotifPostPermission = np;
    });
  }

  Future<void> _refreshAppsUsage() async {
    final usage = await NativeBridge.getAllAppsUsage();
    if (!mounted) return;
    setState(() => appsUsage = usage);
    final total = usage.values.fold<int>(0, (a, b) => a + b);
    final youtubeMins = usage['com.google.android.youtube'] ?? 0;
    // Just the "All Apps Usage Today" display total - NOT weekly distraction.
    // Weekly distraction is now tracked natively, scoped specifically to
    // time spent on apps DURING a study session (see
    // StudyForegroundService.kt), which is the more meaningful signal and
    // avoids two different places trying to credit the same weekly number.
    if (email.isNotEmpty) {
      FirebaseFirestore.instance.collection('students').doc(email).set(
        {'totalAppMins': total, 'youtubeMins': youtubeMins},
        SetOptions(merge: true),
      ).catchError((_) {});
    }
  }

  Future<void> _refreshLastSession() async {
    if (email.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(email).get();
      final data = doc.data();
      if (data == null || !mounted) return;
      final rawUsage = data['lastSessionAppUsage'];
      setState(() {
        lastSessionAppUsage = rawUsage is Map
            ? rawUsage.map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
            : {};
        lastSessionDurationMins = (data['lastSessionDurationMins'] ?? 0) as int;
      });
    } catch (_) {}
  }

  Future<void> _refreshOffline() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => offlineMs = prefs.getInt('offline_study_ms') ?? 0);
  }

  void _startTicker() {
    _timerTicker?.cancel();
    _timerTicker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final prefs = await SharedPreferences.getInstance();
      final startMs = prefs.getInt('study_start_ms');
      if (startMs != null) {
        final elapsed = ((DateTime.now().millisecondsSinceEpoch - startMs) / 1000).floor();
        if (mounted) setState(() => studySeconds = elapsed);
      }
    });
  }

  Future<void> _toggleStudy() async {
    final prefs = await SharedPreferences.getInstance();
    if (!isStudying) {
      await prefs.setBool('isStudying', true);
      await prefs.setInt('study_start_ms', DateTime.now().millisecondsSinceEpoch);
      await NativeBridge.startStudyService();
      setState(() {
        isStudying = true;
        studySeconds = 0;
      });
      _startTicker();
    } else {
      await prefs.setBool('isStudying', false);
      await NativeBridge.stopStudyService();
      _timerTicker?.cancel();
      setState(() => isStudying = false);
      // Native finalizes the session (offline time, weekly credit, and the
      // per-app "during session" breakdown) right when Stop is tapped - give
      // it a moment to land in Firestore, then pull the fresh numbers in.
      await Future.delayed(const Duration(seconds: 2));
      await _refreshOffline();
      await _refreshLastSession();
    }
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yt_history_raw');
    await prefs.remove('last_processed_title');
    setState(() => ytHistory = []);
    if (email.isNotEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .doc(email)
          .collection('history')
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit().catchError((_) {});
      await FirebaseFirestore.instance
          .collection('students')
          .doc(email)
          .set({'historyCount': 0}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final topApps = appsUsage.entries.where((e) => e.value >= 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalAppMins = appsUsage.values.fold<int>(0, (a, b) => a + b);
    final offlineMins = (offlineMs / 60000).floor();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _refreshAppsUsage();
            await _refreshOffline();
            await _refreshPermissions();
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!hasUsagePermission || !hasNotifPermission || !hasNotifPostPermission) _permissionBanner(),
              if (!hasUsagePermission || !hasNotifPermission || !hasNotifPostPermission) const SizedBox(height: 16),

              // Code card
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hi, $name', style: const TextStyle(fontSize: 13, color: kMuted)),
                          const SizedBox(height: 4),
                          Text(code,
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 4, color: kBlack)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: kMuted),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Row 2: Study timer + Offline card
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Study Timer', style: TextStyle(fontSize: 13, color: kMuted)),
                          const SizedBox(height: 8),
                          Text(fmtHms(studySeconds),
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800, color: kBlack)),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isStudying ? kRed : kGreen,
                              ),
                              onPressed: _toggleStudy,
                              child: Text(isStudying ? 'Stop' : 'Start Studying'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Offline Study', style: TextStyle(fontSize: 13, color: kMuted)),
                          const SizedBox(height: 4),
                          const Text('Screen OFF = Study', style: TextStyle(fontSize: 10, color: kMuted)),
                          const SizedBox(height: 8),
                          Text(fmtMinutes(offlineMins),
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800, color: kBlack)),
                          const SizedBox(height: 6),
                          Text('${topApps.length} apps tracked', style: const TextStyle(fontSize: 11, color: kMuted)),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: totalAppMins == 0 ? 0 : (offlineMins / (offlineMins + totalAppMins)).clamp(0, 1),
                              minHeight: 6,
                              backgroundColor: kCardBorder,
                              valueColor: const AlwaysStoppedAnimation(kGreen),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // This Week (resets automatically every Monday)
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('This Week - Studied', style: TextStyle(fontSize: 11, color: kMuted)),
                          const SizedBox(height: 4),
                          Text(fmtMinutes((weekStudyMs / 60000).floor()),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kGreen)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 32, color: kCardBorder),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('This Week - Distracted', style: TextStyle(fontSize: 11, color: kMuted)),
                          const SizedBox(height: 4),
                          Text(fmtMinutes((weekDistractionMs / 60000).floor()),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kRed)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // During Last Study Session - which apps were used, and for how
              // long, WHILE a study session was active (computed natively by
              // comparing app-usage at session start vs session end).
              if (lastSessionAppUsage.isNotEmpty) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle('During Last Study Session'),
                      if (lastSessionDurationMins > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 8),
                          child: Text('Session length: ${fmtMinutes(lastSessionDurationMins)}',
                              style: const TextStyle(fontSize: 11, color: kMuted)),
                        ),
                      ...(lastSessionAppUsage.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                          .take(6)
                          .map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                        child: Text(friendlyAppName(e.key),
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13, color: kBlack))),
                                    Text(fmtMinutes(e.value),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kRed)),
                                  ],
                                ),
                              )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Clone/dual-space app check
              if (cloneCheckDone) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle('Dual / Cloned App Check'),
                      const SizedBox(height: 8),
                      if (cloneAppsFound.isEmpty)
                        const Text('No cloning apps detected among the common ones we check for.',
                            style: TextStyle(fontSize: 13, color: kBlack))
                      else
                        ...cloneAppsFound.map((name) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: kRed, size: 16),
                                  const SizedBox(width: 8),
                                  Text(name, style: const TextStyle(fontSize: 13, color: kBlack)),
                                ],
                              ),
                            )),
                      const SizedBox(height: 8),
                      Builder(builder: (context) {
                        final info = brandDualAppInfo(deviceBrand);
                        if (info != null) {
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFDBA74)),
                            ),
                            child: Text(
                              'This is a ${deviceBrand.isEmpty ? "" : deviceBrand} phone, which has a '
                              'built-in "${info.featureName}" feature we cannot see into - that\'s a '
                              'limit of what any regular app is allowed to see on Android, not '
                              'something that can be fixed in code. Check yourself: ${info.whereToCheck}.',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C2D12), height: 1.3),
                            ),
                          );
                        }
                        return const Text(
                          'Note: some phone brands (Xiaomi, Samsung, Oppo, Vivo) have a built-in '
                          '"Dual Apps" / "App Clone" / "Secure Folder" feature that creates a fully '
                          'separate copy this check cannot see at all - that\'s a limit of what any '
                          'regular app is allowed to see on Android, not something we can fix in code.',
                          style: TextStyle(fontSize: 11, color: kMuted, height: 1.3),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // All Apps Usage Today
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SectionTitle('All Apps Usage Today'),
                        TextButton.icon(
                          onPressed: _refreshAppsUsage,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (topApps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No usage data yet', style: TextStyle(color: kMuted)),
                      )
                    else
                      ...topApps.take(6).map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                    child: Text(friendlyAppName(e.key),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, color: kBlack))),
                                Text(fmtMinutes(e.value),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kMuted)),
                              ],
                            ),
                          )),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // YouTube Titles
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SectionTitle('YouTube Titles'),
                        TextButton(onPressed: _clearHistory, child: const Text('Clear')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (ytHistory.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No titles yet', style: TextStyle(color: kMuted)),
                      )
                    else
                      ...ytHistory.take(10).map((e) {
                        final parts = e.split('|||');
                        final title = parts.isNotEmpty ? parts[0] : '';
                        final time = parts.length > 1 ? parts[1] : '';
                        final type = parts.length > 2 ? parts[2] : 'DISTRACTION';
                        return _historyTile(title, time, type);
                      }),
                  ],
                ),
              ),
              footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyTile(String title, String time, String type) {
    final color = type == 'STUDY' ? kGreen : kRed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, color: kBlack)),
                Text(time, style: const TextStyle(fontSize: 11, color: kMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _permissionBanner() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: kRed, size: 20),
              SizedBox(width: 8),
              Text('Permissions needed', style: TextStyle(fontWeight: FontWeight.w700, color: kBlack)),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasUsagePermission)
            _permRow('Usage Access', 'Required to track app usage', NativeBridge.openUsageSettings),
          if (!hasNotifPermission)
            _permRow('Notification Access', 'Required to detect YouTube titles', NativeBridge.openNotifSettings),
          if (!hasNotifPostPermission)
            _permRow('Show Notifications', 'Required so the study timer notification can appear',
                NativeBridge.requestNotifPostPermission),
        ],
      ),
    );
  }

  Widget _permRow(String title, String subtitle, Future<void> Function() onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBlack)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: kMuted)),
              ],
            ),
          ),
          OutlinedButton(onPressed: onTap, child: const Text('Enable')),
        ],
      ),
    );
  }
}

// ============================================================================
// PARENT LOGIN
// ============================================================================
class ParentLoginScreen extends StatefulWidget {
  const ParentLoginScreen({super.key});
  @override
  State<ParentLoginScreen> createState() => _ParentLoginScreenState();
}

class _ParentLoginScreenState extends State<ParentLoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _link() async {
    final email = _email.text.trim().toLowerCase();
    final code = _code.text.trim();
    if (email.isEmpty || code.isEmpty) {
      setState(() => _error = 'Please enter both fields');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance.collection('students').doc(email).get();
      if (doc.exists && doc.data() != null && doc.data()!['code'].toString() == code) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('linkedCode', code);
        await prefs.setString('linkedEmail', email);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ParentDashboard(email: email, code: code)),
        );
      } else {
        setState(() => _error = 'Invalid email or code');
      }
    } catch (e) {
      setState(() => _error = 'Could not reach Firebase: $e. If this is your first run, check that you replaced android/app/google-services.json with your real Firebase file (see README).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parent Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Link to your child',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBlack)),
              const SizedBox(height: 4),
              const Text('Enter the email and code your child shared with you',
                  style: TextStyle(fontSize: 13, color: kMuted)),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Child\'s Email'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Child\'s Code'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: kRed, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _link,
                  child: _loading
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Link'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PARENT DASHBOARD
// ============================================================================
class ParentDashboard extends StatelessWidget {
  final String email;
  final String code;
  const ParentDashboard({super.key, required this.email, required this.code});

  // Clears the saved parent session so SessionGate falls through to Role
  // Select next launch. Nothing about the child's account or data is
  // touched - linking again later with the same email + code works exactly
  // as before.
  Future<void> _logoutParent(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?'),
        content: const Text('You can link again anytime with your child\'s email and code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('linkedEmail');
    await prefs.remove('linkedCode');

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentDoc = FirebaseFirestore.instance.collection('students').doc(email);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () => _logoutParent(context),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: studentDoc.snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            final offlineMs = (data['offlineStudyMs'] ?? 0) as int;
            final totalAppMins = (data['totalAppMins'] ?? 0) as int;
            final offlineMins = (offlineMs / 60000).floor();
            final totalMins = offlineMins + totalAppMins;
            final youtubeMins = (data['youtubeMins'] ?? 0) as int;
            final weekStudyMins = (data['weekStudyMins'] ?? 0) as int;
            final weekDistractionMins = (data['weekDistractionMins'] ?? 0) as int;
            final rawSessionUsage = data['lastSessionAppUsage'];
            final lastSessionAppUsage = rawSessionUsage is Map
                ? rawSessionUsage.map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
                : <String, int>{};
            final lastSessionDurationMins = (data['lastSessionDurationMins'] ?? 0) as int;
            final rawCloneApps = data['cloneAppsDetected'];
            final cloneAppsDetected = rawCloneApps is List ? List<String>.from(rawCloneApps) : <String>[];
            final deviceBrand = (data['deviceBrand'] ?? '') as String;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Linked Code: $code', style: const TextStyle(fontSize: 13, color: kMuted)),
                      Text(email, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBlack)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _miniStat('Offline', fmtMinutes(offlineMins)),
                          _miniStat('Total', fmtMinutes(totalMins)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Stats row
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _statBlock('YouTube', fmtMinutes(youtubeMins)),
                          _statBlock('Offline', fmtMinutes(offlineMins)),
                          _statBlock('Total', fmtMinutes(totalMins)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: totalMins == 0 ? 0 : (offlineMins / totalMins).clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: kCardBorder,
                          valueColor: const AlwaysStoppedAnimation(kGreen),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // This Week - real totals, resets automatically every Monday
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('This Week - Studied', style: TextStyle(fontSize: 11, color: kMuted)),
                            const SizedBox(height: 4),
                            Text(fmtMinutes(weekStudyMins),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kGreen)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 32, color: kCardBorder),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('This Week - Distracted', style: TextStyle(fontSize: 11, color: kMuted)),
                            const SizedBox(height: 4),
                            Text(fmtMinutes(weekDistractionMins),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kRed)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Clone/dual-space app check
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle('Dual / Cloned App Check'),
                      const SizedBox(height: 8),
                      if (cloneAppsDetected.isEmpty)
                        const Text('No cloning apps detected among the common ones we check for.',
                            style: TextStyle(fontSize: 13, color: kBlack))
                      else
                        ...cloneAppsDetected.map((name) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: kRed, size: 16),
                                  const SizedBox(width: 8),
                                  Text(name, style: const TextStyle(fontSize: 13, color: kBlack)),
                                ],
                              ),
                            )),
                      const SizedBox(height: 8),
                      Builder(builder: (context) {
                        final info = brandDualAppInfo(deviceBrand);
                        if (info != null) {
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFDBA74)),
                            ),
                            child: Text(
                              'This is a ${deviceBrand.isEmpty ? "" : deviceBrand} phone, which has a '
                              'built-in "${info.featureName}" feature we cannot see into - that\'s a '
                              'limit of what any regular app is allowed to see on Android, not '
                              'something that can be fixed in code. Have your child check: '
                              '${info.whereToCheck}.',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C2D12), height: 1.3),
                            ),
                          );
                        }
                        return const Text(
                          'Note: some phone brands (Xiaomi, Samsung, Oppo, Vivo) have a built-in '
                          '"Dual Apps" / "App Clone" / "Secure Folder" feature that creates a fully '
                          'separate copy this check cannot see at all - that\'s a limit of what any '
                          'regular app is allowed to see on Android, not something that can be fixed '
                          'in code.',
                          style: TextStyle(fontSize: 11, color: kMuted, height: 1.3),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // During Last Study Session - exactly what was requested:
                // per-student, time-only visibility into which apps were
                // used and for how long WHILE studying. Never shows video
                // titles or content - that stays parent/student-only.
                if (lastSessionAppUsage.isNotEmpty) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle('During Last Study Session'),
                        if (lastSessionDurationMins > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 8),
                            child: Text('Session length: ${fmtMinutes(lastSessionDurationMins)}',
                                style: const TextStyle(fontSize: 11, color: kMuted)),
                          ),
                        ...(lastSessionAppUsage.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                            .take(6)
                            .map((e) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                          child: Text(friendlyAppName(e.key),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 13, color: kBlack))),
                                      Text(fmtMinutes(e.value),
                                          style: const TextStyle(
                                              fontSize: 13, fontWeight: FontWeight.w600, color: kRed)),
                                    ],
                                  ),
                                )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Weekly focus (illustrative day-by-day chart - see README)
                _weeklyFocusCard(),
                const SizedBox(height: 16),

                // What was studied today
                _historySection(
                  title: 'What Was Studied Today',
                  query: studentDoc.collection('history').where('type', isEqualTo: 'STUDY').orderBy('createdAt', descending: true).limit(50),
                  color: kGreen,
                ),
                const SizedBox(height: 16),

                _historySection(
                  title: 'Distractions Detected',
                  query: studentDoc.collection('history').where('type', isEqualTo: 'DISTRACTION').orderBy('createdAt', descending: true).limit(50),
                  color: kRed,
                ),
                const SizedBox(height: 16),

                _historySection(
                  title: 'YouTube History',
                  query: studentDoc.collection('history').orderBy('createdAt', descending: true).limit(50),
                  color: kMuted,
                ),

                footer(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBlack)),
        ],
      ),
    );
  }

  Widget _statBlock(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kBlack)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
      ],
    );
  }

  Widget _weeklyFocusCard() {
    final dailyStatsRef = FirebaseFirestore.instance.collection('students').doc(email).collection('dailyStats');

    // Monday-Sunday of the CURRENT calendar week - matching the "This Week"
    // totals above (which already reset every Monday, natively) rather than
    // a rolling 7-day window. Days later than today (if today isn't Sunday
    // yet) simply have no document and correctly show as 0 - they haven't
    // happened yet, not because of a bug.
    final now = DateTime.now();
    final todayIndex = now.weekday - 1; // Monday=0 .. Sunday=6
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: todayIndex));
    final dates = List.generate(7, (i) => monday.add(Duration(days: i)));
    final dateKeys = dates.map(_dateKey).toList();
    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S']; // Monday..Sunday

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: dailyStatsRef.where(FieldPath.documentId, whereIn: dateKeys).snapshots(),
      builder: (context, snap) {
        final studyHoursByDate = <String, double>{};
        for (final doc in snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          final studyMs = (doc.data()['studyMs'] ?? 0) as int;
          studyHoursByDate[doc.id] = studyMs / 3600000.0;
        }

        const maxHours = 8.0; // reasonable ceiling for a full day of study
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('WEEKLY FOCUS (MON-SUN)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: kMuted)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final isToday = i == todayIndex;
                  final hours = studyHoursByDate[dateKeys[i]] ?? 0.0;
                  final h = (hours / maxHours * 80).clamp(4.0, 80.0);
                  final weekdayLetter = dayLetters[i];
                  return Column(
                    children: [
                      Container(
                        width: 22,
                        height: h,
                        decoration: BoxDecoration(
                          color: isToday ? kBlack : kGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(weekdayLetter,
                          style: TextStyle(
                              fontSize: 11,
                              color: isToday ? kBlack : kMuted,
                              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
                    ],
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _historySection({
    required String title,
    required Query<Map<String, dynamic>> query,
    required Color color,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No titles yet', style: TextStyle(color: kMuted)),
                );
              }
              return Column(
                children: docs.take(20).map((d) {
                  final data = d.data();
                  final t = (data['title'] ?? '').toString();
                  final time = (data['time'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t, style: const TextStyle(fontSize: 13, color: kBlack)),
                              Text(time, style: const TextStyle(fontSize: 11, color: kMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
