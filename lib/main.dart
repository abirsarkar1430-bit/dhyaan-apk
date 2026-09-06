import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';

void main() => runApp(DhyaanApp());

class DhyaanApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, title: 'Dhyaan', theme: ThemeData(scaffoldBackgroundColor: Color(0xFFF8FAFC)), home: RoleSelect());
  }
}

class RoleSelect extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.self_improvement, size: 72, color: Colors.black87),
      SizedBox(height:12),
      Text("Dhyaan", style: TextStyle(fontSize:44, fontWeight: FontWeight.bold)),
      Text("Padhai ka Sach", style: TextStyle(color: Colors.grey, fontSize:16)),
      SizedBox(height:48),
      _card(context, "I am a Student", "Track focus + offline study", Icons.school, true),
      SizedBox(height:16),
      _card(context, "I am a Parent", "Full report with charts", Icons.family_restroom, false),
      SizedBox(height:40),
      Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize:11, color: Colors.grey))
    ]))));
  }
  Widget _card(BuildContext c, String t, String s, IconData ic, bool isStu){
    return InkWell(onTap: () async { final prefs = await SharedPreferences.getInstance(); await prefs.setBool("isStudent", isStu); Navigator.push(c, MaterialPageRoute(builder: (_)=> LoginScreen(isStudent: isStu))); }, child: Container(width: double.infinity, padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)), child: Row(children: [Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)), child: Icon(ic)), SizedBox(width:16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(fontWeight: FontWeight.bold)), Text(s, style: TextStyle(fontSize:12, color: Colors.grey))])])));
  }
}

class LoginScreen extends StatefulWidget { final bool isStudent; LoginScreen({required this.isStudent}); @override State<LoginScreen> createState()=> _LoginScreenState(); }
class _LoginScreenState extends State<LoginScreen> {
  TextEditingController nameCtrl = TextEditingController();
  TextEditingController codeCtrl = TextEditingController();
  String existingCode = "";
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { final p = await SharedPreferences.getInstance(); setState(()=> existingCode = p.getString("linkCode") ?? p.getString("student_code") ?? ""); }
  @override Widget build(BuildContext context){
    return Scaffold(appBar: AppBar(title: Text(widget.isStudent ? "Student Login" : "Parent Login")), body: Padding(padding: EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if(widget.isStudent)...[
        Text("Student Login", style: TextStyle(fontSize:24, fontWeight: FontWeight.bold)),
        if(existingCode.isNotEmpty) Container(margin: EdgeInsets.only(top:12), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)), child: Text("Existing code: \$existingCode will be reused", style: TextStyle(fontWeight: FontWeight.bold))),
        SizedBox(height:24),
        TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "Your Name", border: OutlineInputBorder())),
        SizedBox(height:20),
        SizedBox(width: double.infinity, height:50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white), onPressed: () async { final prefs = await SharedPreferences.getInstance(); String code = existingCode.isNotEmpty ? existingCode : (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString().substring(0,6); await prefs.setString("linkCode", code); await prefs.setString("student_code", code); await prefs.setString("student_name", nameCtrl.text.isEmpty ? "Aman" : nameCtrl.text); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> StudentDashboard())); }, child: Text(existingCode.isNotEmpty ? "Continue with same code" : "Continue"))),
      ] else ...[
        Text("Parent Login", style: TextStyle(fontSize:24, fontWeight: FontWeight.bold)),
        SizedBox(height:24),
        TextField(controller: codeCtrl, decoration: InputDecoration(labelText: "Child Code", border: OutlineInputBorder(), hintText: existingCode.isNotEmpty ? "Try \$existingCode" : "e.g. 482913")),
        SizedBox(height:20),
        SizedBox(width: double.infinity, height:50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white), onPressed: () async { final prefs = await SharedPreferences.getInstance(); await prefs.setString("linkedCode", codeCtrl.text); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> ParentDashboard())); }, child: Text("Link & View FULL Report"))),
        if(existingCode.isNotEmpty) Padding(padding: EdgeInsets.only(top:16), child: Text("Tip: Student code on this phone is \$existingCode", style: TextStyle(fontSize:12, color: Colors.grey))),
      ],
      Spacer(),
      Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize:11, color: Colors.grey)))
    ])));
  }
}

class StudentDashboard extends StatefulWidget { @override State<StudentDashboard> createState()=> _StudentDashboardState(); }
class _StudentDashboardState extends State<StudentDashboard> {
  static const channel = MethodChannel("com.dhyaan.app/usage");
  String linkCode = ""; String studentName = "";
  List<Map<String,String>> titles = [];
  Map<String,int> appUsage = {};
  int offlineMs = 0;
  bool isStudying = false; int studySec = 0;
  Timer? timer; Timer? poll;
  bool hasUsage = false; bool hasNotif = false;
  @override void initState(){ super.initState(); _loadAll(); _polling(); }
  @override void dispose(){ timer?.cancel(); poll?.cancel(); super.dispose(); }
  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState((){
      linkCode = prefs.getString("linkCode") ?? prefs.getString("student_code") ?? "000000";
      studentName = prefs.getString("student_name") ?? "Aman";
    });
    await _loadTitles(); await _loadUsage(); await _loadOffline(); await _checkPerm();
  }
  Future<void> _loadTitles() async { final prefs = await SharedPreferences.getInstance(); List<String>? saved = prefs.getStringList("history"); if(saved!=null){ setState(()=> titles = saved.map((e){ var p=e.split("|||"); return {"title":p[0],"time":p.length>1?p[1]:"now","type":p.length>2?p[2]:"STUDY"}; }).toList()); } }
  Future<void> _loadUsage() async { try{ final Map<dynamic,dynamic> res = await channel.invokeMethod("getAllAppsUsage"); Map<String,int> m={}; res.forEach((k,v){ m[k.toString()] = (v as int) ~/ 60000; }); setState(()=> appUsage=m); } catch(e){ try{ final int ms = await channel.invokeMethod("getYoutubeUsage"); setState(()=> appUsage={"com.google.android.youtube": ms~/60000}); } catch(_){} } }
  Future<void> _loadOffline() async { try{ final int ms = await channel.invokeMethod("getOfflineStudyTime"); setState(()=> offlineMs=ms); } catch(e){ final prefs=await SharedPreferences.getInstance(); setState(()=> offlineMs = prefs.getInt("offline_study_ms") ?? 0); } }
  Future<void> _checkPerm() async { try{ final bool u = await channel.invokeMethod("hasUsagePermission"); final bool n = await channel.invokeMethod("hasNotifPermission"); setState(()=> {hasUsage=u, hasNotif=n}); } catch(_){} }
  void _polling(){ poll = Timer.periodic(Duration(seconds:3), (_) async { final prefs = await SharedPreferences.getInstance(); String t = prefs.getString("flutter.last_yt_title") ?? ""; String last = prefs.getString("last_processed_title") ?? ""; if(t.isNotEmpty && t!=last){ await prefs.setString("last_processed_title", t); await _addTitle(t); } await _loadOffline(); await _checkPerm(); }); }
  Future<void> _addTitle(String title, {bool save=true}) async { if(title.trim().isEmpty) return; String low=title.toLowerCase(); List<String> k=["physics","chemistry","math","biology","neet","jee","ncert","lecture","class","trick","formula","pyq","electrostatics"]; bool isStudy=k.any((x)=> low.contains(x)); String type=isStudy?"STUDY":"DISTRACTION"; String time=DateFormat('hh:mm a').format(DateTime.now()); if(!save){ setState(()=> titles.insert(0, {"title":title,"time":time,"type":type})); return; } final prefs=await SharedPreferences.getInstance(); List<String> saved=prefs.getStringList("history")??[]; saved.insert(0, "\$title|||\$time|||\$type"); if(saved.length>40) saved=saved.sublist(0,40); await prefs.setStringList("history", saved); setState(()=> titles=saved.map((e){ var p=e.split("|||"); return {"title":p[0],"time":p.length>1?p[1]:"now","type":p.length>2?p[2]:"STUDY"}; }).toList()); }
  Future<void> _clear() async { final prefs=await SharedPreferences.getInstance(); await prefs.remove("history"); await prefs.remove("flutter.last_yt_title"); await prefs.remove("last_processed_title"); setState(()=> titles=[]); }
  void _toggle(){ if(isStudying){ timer?.cancel(); setState(()=> isStudying=false); } else { setState(()=> isStudying=true); timer=Timer.periodic(Duration(seconds:1), (_)=> setState(()=> studySec++)); } }
  String _fmt(int s){ int h=s~/3600,m=(s%3600)~/60,sec=s%60; if(h>0) return "\${h}h \${m}m \${sec}s"; if(m>0) return "\${m}m \${sec}s"; return "\${sec}s"; }
  String _fmtMs(int ms){ int m=ms~/60000,h=m~/60; if(h>0) return "\${h}h \${m%60}m offline"; return "\${m}m offline"; }
  @override Widget build(BuildContext context){
    int total = appUsage.values.fold(0, (a,b)=> a+b);
    return Scaffold(appBar: AppBar(title: Text("Hi, \$studentName"), actions: [IconButton(icon: Icon(Icons.delete), onPressed: _clear)]), body: ListView(padding: EdgeInsets.all(16), children: [
      if(!hasUsage || !hasNotif) Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.warning, size:18), SizedBox(width:6), Text("Permissions needed - tap Grant to open Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize:13))]),
        SizedBox(height:8),
        if(!hasUsage) Row(children: [Expanded(child: Text("Usage Access: for all apps + screen OFF time", style: TextStyle(fontSize:12))), ElevatedButton(onPressed: () async { await channel.invokeMethod("openUsageSettings"); }, child: Text("Grant Usage"))]),
        SizedBox(height:6),
        if(!hasNotif) Row(children: [Expanded(child: Text("Notification Access: for YouTube title", style: TextStyle(fontSize:12))), ElevatedButton(onPressed: () async { await channel.invokeMethod("openNotifSettings"); }, child: Text("Grant Notif"))]),
      ])),
      if(!hasUsage || !hasNotif) SizedBox(height:12),
      Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Your Code (permanent)", style: TextStyle(color: Colors.grey, fontSize:11)), Text(linkCode, style: TextStyle(fontSize:30, fontWeight: FontWeight.bold, letterSpacing:3)), Text("Wont change when switching", style: TextStyle(fontSize:10, color: Colors.grey))]),
        IconButton(onPressed: (){ Clipboard.setData(ClipboardData(text: linkCode)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied \$linkCode"))); }, icon: Icon(Icons.copy), style: IconButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white))
      ])),
      SizedBox(height:12),
      Row(children: [
        Expanded(child: Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: isStudying ? Color(0xFFDCFCE7) : Colors.black, borderRadius: BorderRadius.circular(16)), child: Column(children: [Text(isStudying ? "STUDYING" : "Offline Study", style: TextStyle(color: isStudying ? Colors.green.shade800 : Colors.white70, fontSize:11)), SizedBox(height:6), Text(isStudying ? _fmt(studySec) : _fmtMs(offlineMs), style: TextStyle(color: isStudying ? Colors.green.shade900 : Colors.white, fontWeight: FontWeight.bold, fontSize:16)), SizedBox(height:8), SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: isStudying ? Colors.red : Colors.white, foregroundColor: isStudying ? Colors.white : Colors.black), onPressed: _toggle, child: Text(isStudying ? "Stop" : "Start Studying")))]))),
        SizedBox(width:12),
        Expanded(child: Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Screen OFF = Study", style: TextStyle(fontSize:11, color: Colors.grey)), Text(_fmtMs(offlineMs), style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height:4), Text("\${total}m total apps today", style: TextStyle(fontSize:11, color: Colors.grey)), SizedBox(height:8), LinearProgressIndicator(value: total>0 ? (offlineMs~/60000)/((offlineMs~/60000)+total) : 0.6, color: Colors.green)]))),
      ]),
      SizedBox(height:12),
      Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("All Apps Usage Today", style: TextStyle(fontWeight: FontWeight.bold)), IconButton(icon: Icon(Icons.refresh, size:18), onPressed: () async { await _loadUsage(); await _loadOffline(); })]),
        if(appUsage.isEmpty) Text("Grant Usage Access then Refresh", style: TextStyle(fontSize:12, color: Colors.grey))
        else ...appUsage.entries.take(6).map((e){ String name = e.key.contains("youtube") ? "YouTube" : e.key.contains("instagram") ? "Instagram" : e.key.contains("whatsapp") ? "WhatsApp" : e.key.split(".").last; return Padding(padding: EdgeInsets.only(bottom:6), child: Row(children: [Expanded(child: Text(name)), Text("\${e.value}m")])); }).toList(),
      ])),
      SizedBox(height:16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("YouTube Titles", style: TextStyle(fontWeight: FontWeight.bold)), TextButton(onPressed: _clear, child: Text("Clear"))]),
      Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)), child: Row(children: [Text("Preview (not saved):", style: TextStyle(fontSize:11, fontWeight: FontWeight.bold)), SizedBox(width:8), ElevatedButton(onPressed: ()=> _addTitle("Electrostatics One Shot", save:false), child: Text("Study", style: TextStyle(fontSize:11))), SizedBox(width:6), ElevatedButton(onPressed: ()=> _addTitle("CARRYMINATI ROAST", save:false), child: Text("Distraction", style: TextStyle(fontSize:11)))])),
      SizedBox(height:8),
      if(titles.isEmpty) Container(padding: EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [Icon(Icons.ondemand_video, color: Colors.grey.shade300), Text("No titles yet - Play YouTube", style: TextStyle(fontSize:12, color: Colors.grey))]))
      else ...titles.map((it)=> Container(margin: EdgeInsets.only(bottom:8), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(width:4, color: it["type"]=="STUDY"? Colors.green : Colors.red))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(it["title"]!, style: TextStyle(fontWeight: FontWeight.bold, fontSize:13)), Row(children: [Text(it["time"]!, style: TextStyle(fontSize:11, color: Colors.grey)), Spacer(), Container(padding: EdgeInsets.symmetric(horizontal:6, vertical:2), decoration: BoxDecoration(color: it["type"]=="STUDY"? Color(0xFFDCFCE7) : Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)), child: Text(it["type"]!, style: TextStyle(fontSize:10)))])]))).toList(),
      SizedBox(height:30),
      Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize:11, color: Colors.grey))),
    ]));
  }
}

class ParentDashboard extends StatefulWidget { @override State<ParentDashboard> createState()=> _ParentDashboardState(); }
class _ParentDashboardState extends State<ParentDashboard> {
  List<Map<String,String>> titles=[]; String linked=""; Map<String,int> appUsage={}; int offlineMs=0; static const channel = MethodChannel("com.dhyaan.app/usage");
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { final prefs=await SharedPreferences.getInstance(); linked=prefs.getString("linkedCode") ?? ""; List<String>? saved=prefs.getStringList("history"); if(saved!=null){ setState(()=> titles=saved.map((e){ var p=e.split("|||"); return {"title":p[0],"time":p.length>1?p[1]:"now","type":p.length>2?p[2]:"STUDY"}; }).toList()); } try{ final Map<dynamic,dynamic> res = await channel.invokeMethod("getAllAppsUsage"); Map<String,int> m={}; res.forEach((k,v){ m[k.toString()] = (v as int) ~/60000; }); int off = await channel.invokeMethod("getOfflineStudyTime"); setState(()=> {appUsage=m; offlineMs=off;}); } catch(e){} }
  @override Widget build(BuildContext context){
    int study = titles.where((t)=> t["type"]=="STUDY").length; int distract = titles.length-study; int total = appUsage.values.fold(0, (a,b)=> a+b);
    return Scaffold(appBar: AppBar(title: Text("Parent Report - Full")), body: ListView(padding: EdgeInsets.all(16), children: [
      Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)), child: Text("Linked Code: \$linked | Offline Study: \${offlineMs~/60000}m | Total Apps: \${total}m | \$study Study, \$distract Distractions", style: TextStyle(fontSize:12))),
      SizedBox(height:12),
      Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Aman's Report - Today", style: TextStyle(fontWeight: FontWeight.bold, fontSize:18)),
        SizedBox(height:8),
        Row(children: [ _box("YouTube", "\${appUsage["com.google.android.youtube"] ?? 0}m"), SizedBox(width:8), _box("Offline", "\${offlineMs~/60000}m"), SizedBox(width:8), _box("Total", "\${total}m")]),
        SizedBox(height:12),
        LinearProgressIndicator(value: titles.isEmpty?0.5:study/titles.length, backgroundColor: Colors.red.shade100, color: Colors.green),
      ])),
      SizedBox(height:12),
      Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("WEEKLY FOCUS", style: TextStyle(fontSize:11, color: Colors.grey, fontWeight: FontWeight.bold)), SizedBox(height:12), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [ _bar("M",3.2,false), _bar("T",2.1,false), _bar("W",4.5,false), _bar("T",3.8,false), _bar("F",2.9,false), _bar("S",5.1,true), _bar("S",2.2,false)])])),
      SizedBox(height:12),
      Text("What Was Studied Today", style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height:8),
      ...titles.where((t)=> t["type"]=="STUDY").map((it)=> Container(margin: EdgeInsets.only(bottom:8), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(width:4, color: Colors.green))), child: Text(it["title"]!, style: TextStyle(fontWeight: FontWeight.bold)))).toList(),
      SizedBox(height:12),
      Text("Distractions Detected", style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height:8),
      ...titles.where((t)=> t["type"]=="DISTRACTION").map((it)=> Container(margin: EdgeInsets.only(bottom:8), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(width:4, color: Colors.red))), child: Text(it["title"]!, style: TextStyle(fontWeight: FontWeight.bold)))).toList(),
      SizedBox(height:12),
      Text("YouTube History - What Aman Watched Today", style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height:8),
      ...titles.map((it)=> Container(margin: EdgeInsets.only(bottom:8), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: Text(it["title"]!, style: TextStyle(fontWeight: FontWeight.bold, fontSize:13))), Container(padding: EdgeInsets.symmetric(horizontal:6, vertical:2), decoration: BoxDecoration(color: it["type"]=="STUDY"? Color(0xFFDCFCE7) : Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)), child: Text(it["type"]!, style: TextStyle(fontSize:10)))]))).toList(),
      SizedBox(height:30),
      Center(child: Text("© 2026 Dhyaan • Focus, Measured.", style: TextStyle(fontSize:11, color: Colors.grey))),
    ]));
  }
  Widget _box(String k,String v)=> Expanded(child: Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text(k, style: TextStyle(fontSize:10, color: Colors.grey)), Text(v, style: TextStyle(fontWeight: FontWeight.bold))]))); 
  Widget _bar(String d,double v,bool isToday){ double h=(v/5.1)*60; return Column(children: [Container(width:22, height:h, decoration: BoxDecoration(color: isToday? Colors.black : Color(0xFF10B981), borderRadius: BorderRadius.circular(6))), SizedBox(height:6), Text(d, style: TextStyle(fontSize:11, fontWeight: isToday? FontWeight.bold : FontWeight.normal))]); }
}
