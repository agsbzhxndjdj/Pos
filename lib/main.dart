import 'dart:async';
import 'package:flutter/material.dart';
import 'core/store.dart';
import 'core/services.dart';
import 'screens/pos_screen.dart';
import 'screens/shifts_screen.dart';
import 'screens/refunds_screen.dart';
import 'screens/delivery_screens.dart';
import 'screens/manage_screens.dart';

/* ==========================================================
   1) دالة نقطة الدخول الرئيسية (main)
   ========================================================== */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Session.load();
  await PaymentService.load();
  await DrawerService.load();
  runApp(const PosApp());
}



/* ==========================================================
   2) دالة التطبيق الجذري (PosApp)
   ========================================================== */
class PosApp extends StatelessWidget {
  const PosApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'POS System',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0071E3)),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF0071E3)),
    themeMode: ThemeMode.system,
    home: const Gate(),
  );
}



/* ==========================================================
   3) دالة بوابة الدخول (Gate)
   ========================================================== */
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool? _logged;

  @override
  void initState() {
    super.initState();
    _check();
  }



  Future<void> _check() async {
    final v = await Store.metaGet('loggedIn');
    setState(() => _logged = v == '1');
  }



  @override
  Widget build(BuildContext context) {
    if (_logged == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return _logged! ? const HomeShell() : LoginScreen(onDone: _check);
  }
}



/* ==========================================================
   4) دالة شاشة تسجيل الدخول (LoginScreen)
   ========================================================== */
class LoginScreen extends StatefulWidget {
  final VoidCallback onDone;
  const LoginScreen({super.key, required this.onDone});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController(text: 'admin');
  final _p = TextEditingController(text: 'admin');



  Future<void> _seedUsers() async {
    if ((await Store.list('users')).isNotEmpty) return;
    await Store.upsert('users', 'admin', {'id': 'admin', 'username': 'admin', 'pass': 'admin', 'name': 'المدير', 'branchId': 'main', 'role': 'admin'});
    await Store.upsert('users', 'cashier1', {'id': 'cashier1', 'username': 'cashier', 'pass': '123', 'name': 'كاشير 1', 'branchId': 'main', 'role': 'cashier'});
  }



  Future<void> _login() async {
    await _seedUsers();
    final user = (await Store.list('users')).map((e) => e.data).where((u) => u['username'] == _u.text && u['pass'] == _p.text).firstOrNull;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ بيانات غير صحيحة')));
      return;
    }
    Session.userId = user['id']; Session.userName = user['name']; Session.branchId = user['branchId'];
    await Session.save();
    await Store.metaSet('loggedIn', '1');
    widget.onDone();
  }



  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.point_of_sale, size: 64),
        const SizedBox(height: 12),
        const Text('نظام نقاط البيع', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        TextField(controller: _u, decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _login, child: const Text('تسجيل الدخول'))),
        const SizedBox(height: 10),
        const Text('admin/admin • cashier/123', style: TextStyle(fontSize: 12)),
      ]))))),
  );
}



/* ==========================================================
   5) دالة الصدفة الرئيسية والتنقل (HomeShell)
   ========================================================== */
/* ==========================================================
   5) دالة الصدفة الرئيسية والتنقل (HomeShell) — مصححة
   ========================================================== */
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  int _appsBadge = 0;
  Timer? _timer;



  @override
  void initState() {
    super.initState();
    SyncService.sync();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final c = await DeliveryAppsService.pendingCount();
      if (mounted) setState(() => _appsBadge = c);
    });
  }



  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }



  Future<void> _logout() async {
    if (await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('تسجيل الخروج؟'),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('خروج'))],
        )) != true) return;
    await Store.metaSet('loggedIn', '0');
    setState(() => _i = 0);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Gate()));
  }



  @override
  Widget build(BuildContext context) {
    final screens = [
      PosScreen(branchId: Session.branchId, userId: Session.userId),
      ShiftsScreen(branchId: Session.branchId, userId: Session.userId),
      RefundsScreen(branchId: Session.branchId, userId: Session.userId),
      DeliveryAppsScreen(userId: Session.userId),
      const InternalDeliveriesScreen(),
      const CustomersScreen(),
      const SyncScreen(),
      const SettingsScreen(),
    ];
    const titles = ['نقطة البيع', 'الورديات', 'المرتجعات', 'منصات التوصيل', 'التوصيل الداخلي', 'العملاء', 'المزامنة والفروع', 'الإعدادات'];
    const icons = [Icons.point_of_sale, Icons.badge, Icons.assignment_return, Icons.delivery_dining, Icons.local_shipping, Icons.people, Icons.sync, Icons.settings];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_i]), actions: [
        IconButton(icon: const Icon(Icons.logout), tooltip: 'خروج', onPressed: _logout),
      ]),
      drawer: Drawer(child: ListView(children: [
        DrawerHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
          const Icon(Icons.storefront, size: 40),
          const SizedBox(height: 8),
          Text(Session.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('فرع: ${Session.branchId}', style: Theme.of(context).textTheme.bodySmall),
        ])),
        for (int i = 0; i < screens.length; i++)
          ListTile(
            leading: Icon(icons[i]),
            title: Text(titles[i]),
            trailing: i == 3 && _appsBadge > 0 ? Badge.count(count: _appsBadge) : null,
            selected: _i == i,
            onTap: () { setState(() => _i = i); Navigator.pop(context); },
          ),
      ])),
      body: screens[_i],
    );
  }
}
