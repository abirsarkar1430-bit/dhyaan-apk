
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
// removed
import 'package:intl/intl.dart';

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
              Text("Dhyaan", style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text("Padhai ka Sach", style: TextStyle(color: Colors.grey)),
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
  TextEditingController phone = TextEditingController();
  TextEditingController name = TextEditingController();
  TextEditingController childCode = TextEditingController();
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(widget.isStudent ? "Student Login" : "Parent Login")),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            if(widget.isStudent) ...[
              TextField(controller: name, decoration: InputDecoration(labelText: "Your Name (e.g. Aman)")),
              SizedBox(height: 12),
              TextField(controller: phone, decoration: InputDecoration(labelText: "Phone Number"), keyboardType: TextInputType.phone),
              SizedBox(height: 24),
              ElevatedButton(onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                String code = (100000 + DateTime.now().millisecond*7 % 900000).toString().substring(0,6);
                await prefs.setString("role", "student");
                await prefs.setString("name", name.text.isEmpty ? "Aman" : name.text);
                await prefs.setString("linkCode", code);
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => StudentDashboard()));
              }, child: Text("Continue")),
              SizedBox(height: 12),
              Text("Free for first 100 users • No payment", style: TextStyle(fontSize: 11, color: Colors.grey))
            ] else ...[
              TextField(controller: childCode, decoration: InputDecoration(labelText: "Enter Child Code (e.g. 847291)")),
              SizedBox(height: 12),
              TextField(controller: phone, decoration: InputDecoration(labelText: "Parent Phone")),
              SizedBox(height: 24),
              ElevatedButton(onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString("role", "parent");
                await prefs.setString("linkedCode", childCode.text);
                await prefs.setString("name", "Parent");
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ParentDashboard()));
              }, child: Text("Link & View Report")),
            ]
          ],
        ),
      ),
    );
  }
}

// STUDENT DASHBOARD
class StudentDashboard extends StatefulWidget {
  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}
class _StudentDashboardState extends State<StudentDashboard> {
  static const channel = MethodChannel("com.dhyaan.app/usage");
  String youtubeTime = "Loading...";
  String linkCode = "";
  List<Map<String,String>> titles = [];
  bool isHindi = false;
  int dualAppCount = 0;

  @override
  void initState(){
    super.initState();
    _load();
    _getUsage();
    _checkDualApp();
    channel.setMethodCallHandler((call) async {
      if(call.method == "newTitle"){
        String title = call.arguments;
        _addTitle(title);
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState((){ linkCode = prefs.getString("linkCode") ?? "847291"; });
    // load saved titles
    List<String>? saved = prefs.getStringList("history");
    if(saved!=null){
      setState((){ titles = saved.map((e){ var parts=e.split("|||"); return {"title":parts[0],"time":parts[1],"type":parts[2]}; }).toList(); });
    }
  }

  Future<void> _getUsage() async {
    try{
      final int ms = await channel.invokeMethod("getYoutubeUsage");
      int mins = ms ~/ 60000;
      setState((){ youtubeTime = "${mins ~/60}h ${mins %60}m today"; });
    }catch(e){ setState((){ youtubeTime = "Grant Usage Access"; }); }
  }

  Future<void> _checkDualApp() async {
    try{
      List<Application> apps = await //DeviceApps.getInstalledApplications(includeSystemApps: true);
      int count = apps.where((a)=> a.packageName.toLowerCase().contains("youtube") || a.appName.toLowerCase().contains("youtube")).length;
      setState((){ dualAppCount = count; });
    }catch(e){}
  }

  void _addTitle(String title){
    String type = _classify(title);
    String time = DateFormat("h:mm a").format(DateTime.now());
    setState((){ titles.insert(0, {"title":title,"time":time,"type":type}); });
    _save();
  }

  String _classify(String t){
    String lower = t.toLowerCase();
    List<String> study = ["physics","chemistry","maths","math","biology","neet","jee","ncert","lecture","chapter","class 10","class 12","pyq","formula","electrostatics","physics wallah","alakh","saleem","board","exam","trigonometry","calculus"];
    List<String> dist = ["roast","vlog","comedy","funny","carryminati","gaming","bgmi","free fire","music","song","bigg boss","reaction","meme","shorts"];
    if(study.any((k)=>lower.contains(k))) return "STUDY";
    if(dist.any((k)=>lower.contains(k))) return "DISTRACTION";
    return "UNKNOWN";
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> toSave = titles.map((e)=> "${e["title"]}|||${e["time"]}|||${e["type"]}").toList();
    await prefs.setStringList("history", toSave);
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: Text(isHindi ? "मेरा फोकस" : "My Focus"),
        actions: [TextButton(onPressed: ()=>setState(()=>isHindi=!isHindi), child: Text(isHindi ? "EN" : "HI"))],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          if(dualAppCount>1) Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)), child: Text("⚠️ Dual App Detected - $dualAppCount YouTube apps found", style: TextStyle(fontSize: 12))),
          SizedBox(height: 12),
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [
            Text(isHindi ? "आपका लिंक कोड" : "Your Linking Code", style: TextStyle(color: Colors.grey, fontSize: 12)),
            SizedBox(height: 4),
            Text(linkCode, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
            SizedBox(height: 4),
            Text(isHindi ? "माता-पिता को यह कोड दें" : "Share this code with parent", style: TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          SizedBox(height: 12),
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("YouTube Today", style: TextStyle(fontSize: 12, color: Colors.grey)), Text(youtubeTime, style: TextStyle(fontWeight: FontWeight.bold))]),
            ElevatedButton(onPressed: _getUsage, child: Text("Refresh"))
          ])),
          SizedBox(height: 12),
          Row(children: [
            ElevatedButton(onPressed: () async { await channel.invokeMethod("openUsageSettings"); }, child: Text("Grant Usage Access")),
            SizedBox(width: 8),
            ElevatedButton(onPressed: () async { await channel.invokeMethod("openNotifSettings"); }, child: Text("Grant Notification Access")),
          ]),
          SizedBox(height: 12),
          Text(isHindi ? "आज देखे गए वीडियो के टाइटल" : "Today's YouTube Titles", style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          if(titles.isEmpty) Container(padding: EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [Text("No data yet"), SizedBox(height: 8), Text("Play a YouTube video, title will appear here", style: TextStyle(fontSize: 11, color: Colors.grey)), SizedBox(height: 12), ElevatedButton(onPressed: (){ _addTitle("Electrostatics One Shot L1 | Alakh Pandey"); _addTitle("CARRYMINATI ROASTS BIGG BOSS"); }, child: Text("Add Demo Titles"))])),
          for(var item in titles) Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(width: 4, color: item["type"]=="STUDY"? Colors.green : item["type"]=="DISTRACTION"? Colors.red : Colors.orange))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item["title"]!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              SizedBox(height: 4),
              Row(children: [Text("${item["time"]} • ${item["type"]}", style: TextStyle(fontSize: 11, color: Colors.grey)), Spacer(), Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: item["type"]=="STUDY"? Color(0xFFDCFCE7) : Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)), child: Text(item["type"]!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))])
            ]),
          ),
          SizedBox(height: 80),
          Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey))),
        ],
      ),
    );
  }
}

// PARENT DASHBOARD (reads same local storage for demo, in real Firebase)
class ParentDashboard extends StatefulWidget {
  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}
class _ParentDashboardState extends State<ParentDashboard> {
  bool isHindi = false;
  List<Map<String,String>> titles = [];
  @override
  void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? saved = prefs.getStringList("history");
    if(saved!=null){
      setState((){ titles = saved.map((e){ var parts=e.split("|||"); return {"title":parts[0],"time":parts[1],"type":parts[2]}; }).toList(); });
    } else {
      // demo data for parent
      setState((){ titles = [
        {"title":"Electrostatics One Shot L1 | Alakh Pandey","time":"6:00-6:48 PM","type":"STUDY"},
        {"title":"Chemical Bonding in 30 min","time":"6:50-7:20 PM","type":"STUDY"},
        {"title":"CARRYMINATI ROASTS BIGG BOSS","time":"7:31-7:45 PM","type":"DISTRACTION"},
        {"title":"BGMI Funny Moments","time":"8:10-8:30 PM","type":"DISTRACTION"},
      ];});
    }
  }
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(isHindi ? "माता-पिता रिपोर्ट" : "Parent Report"), actions: [TextButton(onPressed: ()=>setState(()=>isHindi=!isHindi), child: Text(isHindi ? "EN" : "HI"))]),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)), child: Text("⚠️ Dual App Detected - 2 YouTube apps found")),
          SizedBox(height: 12),
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isHindi ? "आज का सार" : "Linked to: Aman • YouTube 3h 24m today", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(isHindi ? "2 पढ़ाई, 2 ध्यान भटकाव" : "2 Study, 2 Distractions detected", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          SizedBox(height: 12),
          for(var item in titles) Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(width: 4, color: item["type"]=="STUDY"? Colors.green : Colors.red))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item["title"]!, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text("${item["time"]} • ${item["type"]} ${item["type"]=="STUDY" ? "98%" : ""}", style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
          SizedBox(height: 80),
          Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey))),
        ],
      ),
    );
  }
}
