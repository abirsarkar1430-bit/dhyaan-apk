
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';

void main() => runApp(DhyaanApp());

class DhyaanApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dhyaan',
      theme: ThemeData(fontFamily: 'Inter', scaffoldBackgroundColor: Color(0xFFF8FAFC)),
      home: RoleSelect(),
    );
  }
}

class RoleSelect extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility, size: 64, color: Colors.black87),
              SizedBox(height: 12),
              Text("Dhyaan", style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text("Padhai ka Sach", style: TextStyle(color: Colors.grey, fontSize: 16)),
              SizedBox(height: 48),
              _roleCard(context, "I am a Student", "Track my YouTube focus", Icons.school, true),
              SizedBox(height: 16),
              _roleCard(context, "I am a Parent", "See my child's report", Icons.family_restroom, false),
              SizedBox(height: 48),
              Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey))
            ],
          ),
        ),
      ),
    );
  }
  Widget _roleCard(BuildContext c, String t, String s, IconData ic, bool isStudent){
    return InkWell(
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => LoginScreen(isStudent: isStudent))),
      child: Container(
        width: double.infinity, padding: EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)), child: Icon(ic)),
          SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(fontWeight: FontWeight.bold)), Text(s, style: TextStyle(fontSize: 12, color: Colors.grey))])
        ]),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final bool isStudent;
  LoginScreen({required this.isStudent});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  TextEditingController name = TextEditingController();
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(widget.isStudent ? "Student Login" : "Parent Login")),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if(widget.isStudent) ...[
              Text("Welcome Student", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text("Your parents will use a code to see your focus report", style: TextStyle(color: Colors.grey)),
              SizedBox(height: 24),
              TextField(controller: name, decoration: InputDecoration(labelText: "Your Name (e.g. Aman)", border: OutlineInputBorder())),
              SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    String code = (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString().substring(0,6);
                    await prefs.setString("role", "student");
                    await prefs.setString("name", name.text.isEmpty ? "Aman" : name.text);
                    await prefs.setString("linkCode", code);
                    await prefs.setString("student_code", code);
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => StudentDashboard()));
                  }, child: Text("Continue →"))),
              SizedBox(height: 12),
              Center(child: Text("Free for first 100 users • No payment", style: TextStyle(fontSize: 11, color: Colors.grey)))
            ] else ...[
              Text("Parent Login", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 24),
              TextField(decoration: InputDecoration(labelText: "Enter Child Code", border: OutlineInputBorder(), hintText: "e.g. 847291"), controller: _parentCodeCtrl),
              SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString("role", "parent");
                    await prefs.setString("linkedCode", _parentCodeCtrl.text);
                    await prefs.setString("name", "Parent");
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ParentDashboard()));
                  }, child: Text("Link & View Report"))),
              SizedBox(height: 12),
              FutureBuilder<SharedPreferences>(future: SharedPreferences.getInstance(), builder: (c,snap){
                String sc = snap.data?.getString("student_code") ?? snap.data?.getString("linkCode") ?? "No code yet - login as student first on this phone (demo)";
                return Text("Demo: Student code on this device is $sc", style: TextStyle(fontSize: 11, color: Colors.grey));
              })
            ],
            Spacer(),
            Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey)))
          ],
        ),
      ),
    );
  }
  TextEditingController _parentCodeCtrl = TextEditingController();
}

class StudentDashboard extends StatefulWidget {
  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}
class _StudentDashboardState extends State<StudentDashboard> {
  static const channel = MethodChannel("com.dhyaan.app/usage");
  String youtubeTime = "Tap Refresh";
  String linkCode = "";
  String studentName = "";
  List<Map<String,String>> titles = [];
  bool isStudying = false;
  int studySeconds = 0;
  Timer? timer;
  Timer? pollTimer;

  @override
  void initState(){
    super.initState();
    _load();
    _getUsage();
    _startPolling();
  }

  @override
  void dispose(){
    timer?.cancel();
    pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState((){
      linkCode = prefs.getString("linkCode") ?? prefs.getString("student_code") ?? "847291";
      studentName = prefs.getString("name") ?? "Aman";
    });
    List<String>? saved = prefs.getStringList("history");
    if(saved!=null){
      setState((){
        titles = saved.map((e){ var parts=e.split("|||"); return {"title":parts[0],"time":parts.length>1?parts[1]:"now","type":parts.length>2?parts[2]:"STUDY"}; }).toList();
      });
    }
  }

  Future<void> _getUsage() async {
    try{
      final int ms = await channel.invokeMethod("getYoutubeUsage");
      int mins = ms ~/ 60000;
      int hrs = mins ~/ 60;
      setState((){ youtubeTime = hrs>0 ? "${hrs}h ${mins%60}m today" : "${mins}m today"; });
    } catch(e){
      setState((){ youtubeTime = "Grant Usage Access to see"; });
    }
  }

  void _startPolling(){
    pollTimer = Timer.periodic(Duration(seconds: 3), (_) async {
      final prefs = await SharedPreferences.getInstance();
      String t = prefs.getString("flutter.last_yt_title") ?? "";
      if(t.isNotEmpty){
        String last = prefs.getString("last_processed_title") ?? "";
        if(t != last){
          await prefs.setString("last_processed_title", t);
          _addTitle(t);
        }
      }
    });
  }

  Future<void> _addTitle(String title) async {
    String low = title.toLowerCase();
    List<String> studyK = ["physics","chemistry","math","biology","neet","jee","ncert","lecture","class 12","class 11","trick","formula","pyq","electrostatics","organic","calculus"];
    bool isStudy = studyK.any((k)=> low.contains(k));
    String type = isStudy ? "STUDY" : "DISTRACTION";
    String time = DateFormat('hh:mm a').format(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    List<String> saved = prefs.getStringList("history") ?? [];
    saved.insert(0, "$title|||$time|||$type");
    if(saved.length>30) saved = saved.sublist(0,30);
    await prefs.setStringList("history", saved);
    await prefs.setString("flutter.last_yt_title", title);
    setState((){
      titles = saved.map((e){ var parts=e.split("|||"); return {"title":parts[0],"time":parts.length>1?parts[1]:"now","type":parts.length>2?parts[2]:"STUDY"}; }).toList();
    });
  }

  void _toggleStudy(){
    if(isStudying){
      timer?.cancel();
      setState(()=> isStudying = false);
    } else {
      setState(()=> isStudying = true);
      timer = Timer.periodic(Duration(seconds: 1), (_){
        setState(()=> studySeconds++);
      });
    }
  }

  String _formatTimer(int s){
    int h = s~/3600;
    int m = (s%3600)~/60;
    int sec = s%60;
    if(h>0) return "${h}h ${m}m ${sec}s";
    if(m>0) return "${m}m ${sec}s";
    return "${sec}s";
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text("Hi, $studentName 👋"), actions: [IconButton(onPressed: ()=>setState((){}), icon: Icon(Icons.refresh))]),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Code card
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Your Linking Code", style: TextStyle(color: Colors.grey, fontSize: 12)),
                SizedBox(height: 4),
                Text(linkCode, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 3)),
                Text("Share with parents", style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              IconButton(onPressed: (){ Clipboard.setData(ClipboardData(text: linkCode)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Code $linkCode copied!"))); }, icon: Icon(Icons.copy), style: IconButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white))
            ]),
          ])),
          SizedBox(height: 12),
          // Timer card with Start Studying
          Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(color: isStudying ? Color(0xFFDCFCE7) : Colors.black, borderRadius: BorderRadius.circular(20)), child: Column(children: [
            Text(isStudying ? "STUDYING..." : "Ready to focus?", style: TextStyle(color: isStudying ? Colors.green.shade800 : Colors.white70, fontSize: 12, letterSpacing: 1)),
            SizedBox(height: 8),
            Text(isStudying ? _formatTimer(studySeconds) : "Start Study Timer", style: TextStyle(color: isStudying ? Colors.green.shade900 : Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isStudying ? Colors.red : Colors.white, foregroundColor: isStudying ? Colors.white : Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _toggleStudy,
                child: Text(isStudying ? "⏹ Stop" : "▶ Start Studying", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
              )
            )
          ])),
          SizedBox(height: 12),
          // YouTube stats
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("YouTube Today", style: TextStyle(fontSize: 12, color: Colors.grey)), SizedBox(height:4), Text(youtubeTime, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            Row(children: [
              ElevatedButton(onPressed: _getUsage, child: Text("Refresh")),
              SizedBox(width: 8),
              IconButton(onPressed: () async { await channel.invokeMethod("openUsageSettings"); }, icon: Icon(Icons.settings), tooltip: "Grant Usage Access")
            ])
          ])),
          SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: () async { await channel.invokeMethod("openUsageSettings"); }, child: Text("Grant Usage"))),
            SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: () async { await channel.invokeMethod("openNotifSettings"); }, child: Text("Grant Notification"))),
          ]),
          SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Today's YouTube Titles", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            TextButton(onPressed: (){
              _addTitle("Electrostatics One Shot L1 | Alakh Pandey");
              _addTitle("CARRYMINATI ROASTS BIGG BOSS - Latest");
              _addTitle("Chemical Bonding in 30 min | NEET");
              _addTitle("BGMI Funny Moments - 1M views");
            }, child: Text("Add Demo"))
          ]),
          SizedBox(height: 8),
          if(titles.isEmpty) Container(padding: EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [Icon(Icons.ondemand_video, size: 48, color: Colors.grey.shade300), SizedBox(height: 12), Text("No videos yet", style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height: 4), Text("Play any YouTube video, title will appear here automatically", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)), SizedBox(height: 16), Text("Or tap 'Add Demo' to see how it looks", style: TextStyle(fontSize: 11, color: Colors.grey))])),

          for(var item in titles) Container(
            margin: EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border(left: BorderSide(width: 5, color: item["type"]=="STUDY"? Colors.green : Colors.red))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item["title"]!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              SizedBox(height: 6),
              Row(children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey),
                SizedBox(width: 4),
                Text(item["time"]!, style: TextStyle(fontSize: 11, color: Colors.grey)),
                Spacer(),
                Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: item["type"]=="STUDY"? Color(0xFFDCFCE7) : Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(20)), child: Text(item["type"]!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: item["type"]=="STUDY"? Colors.green.shade800 : Colors.red.shade800))),
              ])
            ]),
          ),
          SizedBox(height: 30),
          Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey))),
          SizedBox(height: 4),
          Center(child: Text("Made for Bishnupur coaching students", style: TextStyle(fontSize: 10, color: Colors.grey))),
          SizedBox(height: 80),
        ],
      ),
    );
  }
}

class ParentDashboard extends StatefulWidget {
  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}
class _ParentDashboardState extends State<ParentDashboard> {
  List<Map<String,String>> titles = [];
  String linked = "";
  @override
  void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    linked = prefs.getString("linkedCode") ?? "";
    List<String>? saved = prefs.getStringList("history");
    if(saved!=null && saved.isNotEmpty){
      setState((){ titles = saved.map((e){ var parts=e.split("|||"); return {"title":parts[0],"time":parts.length>1?parts[1]:"now","type":parts.length>2?parts[2]:"STUDY"}; }).toList(); });
    } else {
      setState((){ titles = [
        {"title":"Electrostatics One Shot L1 | Alakh Pandey","time":"6:00 PM","type":"STUDY"},
        {"title":"Chemical Bonding in 30 min","time":"6:50 PM","type":"STUDY"},
        {"title":"CARRYMINATI ROASTS BIGG BOSS","time":"7:31 PM","type":"DISTRACTION"},
        {"title":"BGMI Funny Moments","time":"8:10 PM","type":"DISTRACTION"},
      ];});
    }
  }
  @override
  Widget build(BuildContext context){
    int studyCount = titles.where((t)=> t["type"]=="STUDY").length;
    int distractCount = titles.length - studyCount;
    return Scaffold(
      appBar: AppBar(title: Text("Parent Report"), actions: [IconButton(icon: Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Linked to Code: $linked", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text("Aman • YouTube 3h 24m today • $studyCount Study, $distractCount Distractions", style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 12),
            LinearProgressIndicator(value: titles.isEmpty?0:studyCount/titles.length, backgroundColor: Colors.red.shade100, color: Colors.green),
          ])),
          SizedBox(height: 12),
          for(var item in titles) Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(width: 4, color: item["type"]=="STUDY"? Colors.green : Colors.red))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item["title"]!, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text("${item["time"]} • ${item["type"]}", style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
          SizedBox(height: 30),
          Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey))),
        ],
      ),
    );
  }
}
