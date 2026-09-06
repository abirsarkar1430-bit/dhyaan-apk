
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
              Text("© 2026 Dhyaan \u2022 Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey))
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
          CircleAvatar(child: Icon(ic)),
          SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(fontWeight: FontWeight.bold)), Text(s, style: TextStyle(fontSize:12, color: Colors.grey))])
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
  TextEditingController nameCtrl = TextEditingController();
  String code = "";
  @override
  void initState(){ super.initState(); _genCode(); }
  void _genCode(){ code = (100000 + DateTime.now().millisecond % 900000).toString(); }
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(widget.isStudent ? "Student Login" : "Parent Login")),
      body: Padding(padding: EdgeInsets.all(24), child: Column(children: [
        TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "Your Name")),
        SizedBox(height: 20),
        Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Your Code: $code", style: TextStyle(fontWeight: FontWeight.bold)), IconButton(onPressed: (){ Clipboard.setData(ClipboardData(text: code)); }, icon: Icon(Icons.copy))]),
        ),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(widget.isStudent ? "student_name" : "parent_name", nameCtrl.text.isEmpty ? "User" : nameCtrl.text);
            await prefs.setString(widget.isStudent ? "student_code" : "parent_code", code);
            await prefs.setBool("isStudent", widget.isStudent);
            if(widget.isStudent){
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> StudentDashboard()));
            } else {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> ParentDashboard()));
            }
          },
          child: Text("Continue")
        ),
        Spacer(),
        Text("© 2026 Dhyaan \u2022 Focus, Measured.", style: TextStyle(fontSize: 11, color: Colors.grey))
      ])),
    );
  }
}

class StudentDashboard extends StatefulWidget {
  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}
class _StudentDashboardState extends State<StudentDashboard> {
  static const platform = MethodChannel('com.dhyaan.app/usage');
  String lastTitle = "No video yet - play YouTube";
  String category = "Waiting";
  int ytMinutes = 0;
  int focusScore = 85;
  String studentName = "";
  String studentCode = "";
  List<Map<String,String>> history = [];

  @override
  void initState(){
    super.initState();
    _load();
    _checkPermissions();
    _pollTitle();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState((){
      studentName = prefs.getString("student_name") ?? "Student";
      studentCode = prefs.getString("student_code") ?? "000000";
      lastTitle = prefs.getString("last_yt_title") ?? lastTitle;
      history = (prefs.getStringList("history") ?? []).map((e){ final parts = e.split("|"); return {"title": parts[0], "cat": parts.length>1?parts[1]:"Study", "time": parts.length>2?parts[2]:"now"}; }).toList();
      _categorize(lastTitle);
    });
    _getUsage();
  }

  Future<void> _checkPermissions() async {
    try { await platform.invokeMethod("openUsageSettings"); } catch(e){}
  }

  Future<void> _getUsage() async {
    try {
      final int ms = await platform.invokeMethod("getYoutubeUsage");
      setState((){ ytMinutes = (ms / 60000).round(); });
    } catch(e){}
  }

  void _pollTitle() async {
    while(mounted){
      await Future.delayed(Duration(seconds: 3));
      final prefs = await SharedPreferences.getInstance();
      String t = prefs.getString("flutter.last_yt_title") ?? "";
      if(t.isNotEmpty && t != lastTitle){
        setState((){ lastTitle = t; _categorize(t); });
        String entry = "$t|$category|${DateFormat('hh:mm a').format(DateTime.now())}";
        List<String> list = prefs.getStringList("history") ?? [];
        list.insert(0, entry);
        if(list.length>20) list = list.sublist(0,20);
        prefs.setStringList("history", list);
        prefs.setString("last_yt_title", t);
        setState((){ history = list.map((e){ final parts = e.split("|"); return {"title": parts[0], "cat": parts.length>1?parts[1]:"Study", "time": parts.length>2?parts[2]:"now"}; }).toList(); });
      }
    }
  }

  void _categorize(String title){
    String low = title.toLowerCase();
    List<String> studyKeywords = ["math","physics","chemistry","biology","neet","jee","ncert","class","lecture","pyq","trick","formula","coaching"];
    bool isStudy = studyKeywords.any((k)=> low.contains(k));
    category = isStudy ? "STUDY" : "DISTRACTION";
    focusScore = isStudy ? 92 : 38;
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text("Hi, $studentName"), actions: [Center(child: Padding(padding: EdgeInsets.only(right:16), child: Text("Code: $studentCode", style: TextStyle(fontWeight: FontWeight.bold))))]),
      body: ListView(padding: EdgeInsets.all(16), children: [
        Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("NOW PLAYING", style: TextStyle(fontSize:11, letterSpacing:1, color: Colors.grey)),
            SizedBox(height:8),
            Text(lastTitle, style: TextStyle(fontSize:16, fontWeight: FontWeight.bold)),
            SizedBox(height:12),
            Container(padding: EdgeInsets.symmetric(horizontal:10, vertical:4), decoration: BoxDecoration(color: category=="STUDY"?Colors.green.shade100:Colors.red.shade100, borderRadius: BorderRadius.circular(20)),
              child: Text(category, style: TextStyle(fontSize:11, fontWeight: FontWeight.bold, color: category=="STUDY"?Colors.green:Colors.red))),
            SizedBox(height:16),
            Row(children: [
              _stat("YT Today", "$ytMinutes min"),
              SizedBox(width:16),
              _stat("Focus Score", "$focusScore%"),
              SizedBox(width:16),
              _stat("Streak", "3 days"),
            ])
          ]),
        ),
        SizedBox(height:16),
        Text("Today's History", style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height:8),
        ...history.map((h)=> Card(child: ListTile(title: Text(h["title"]??"", maxLines:1, overflow: TextOverflow.ellipsis), subtitle: Text(h["time"]??""), trailing: Container(padding: EdgeInsets.symmetric(horizontal:8, vertical:2), decoration: BoxDecoration(color: h["cat"]=="STUDY"?Colors.green.shade100:Colors.red.shade100, borderRadius: BorderRadius.circular(12)), child: Text(h["cat"]??"", style: TextStyle(fontSize:10)))))).toList(),
        SizedBox(height:24),
        ElevatedButton.icon(onPressed: () async { final p = MethodChannel('com.dhyaan.app/usage'); try{ await p.invokeMethod("openNotifSettings"); }catch(e){} }, icon: Icon(Icons.notifications), label: Text("Enable YouTube Tracking (Notification Access)")),
        SizedBox(height:24),
        Center(child: Text("© 2026 Dhyaan \u2022 Focus, Measured.", style: TextStyle(fontSize:11, color: Colors.grey))),
        SizedBox(height:8),
        Center(child: Text("Made for coaching students - Bishnupur", style: TextStyle(fontSize:10, color: Colors.grey))),
      ]),
    );
  }
  Widget _stat(String k, String v)=> Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: TextStyle(fontSize:10, color: Colors.grey)), Text(v, style: TextStyle(fontWeight: FontWeight.bold))]);
}

class ParentDashboard extends StatefulWidget {
  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}
class _ParentDashboardState extends State<ParentDashboard> {
  TextEditingController codeCtrl = TextEditingController();
  String status = "Enter your child's code to link";
  String lastVideo = "";
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text("Parent View")),
      body: Padding(padding: EdgeInsets.all(24), child: Column(children: [
        TextField(controller: codeCtrl, decoration: InputDecoration(labelText: "Child's Code", border: OutlineInputBorder())),
        SizedBox(height:12),
        ElevatedButton(onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          String sCode = prefs.getString("student_code") ?? "";
          if(codeCtrl.text == sCode && sCode.isNotEmpty){
            setState((){ status = "Linked! Monitoring active"; lastVideo = prefs.getString("last_yt_title") ?? "No video yet"; });
          } else {
            setState((){ status = "Code not found on this device. For demo, use code: $sCode"; });
          }
        }, child: Text("Link Child")),
        SizedBox(height:20),
        Text(status),
        if(lastVideo.isNotEmpty) Padding(padding: EdgeInsets.only(top:16), child: Card(child: ListTile(title: Text("Last watched:"), subtitle: Text(lastVideo)))),
        Spacer(),
        Text("© 2026 Dhyaan \u2022 Focus, Measured.", style: TextStyle(fontSize:11, color: Colors.grey))
      ])),
    );
  }
}
