import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/store.dart';
import '../core/models.dart';
import '../core/services.dart';

/* ==========================================================
   27) دالة شاشة العملاء CRM (CustomersScreen)
   ========================================================== */
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Customer> _list = [];



  @override
  void initState() {
    super.initState();
    _load();
  }



  Future<void> _load() async => setState(() => _list = []);



  Future<void> _refresh() async {
    final l = await CustomerService.all();
    setState(() => _list = l);
  }



  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }



  Future<void> _add() async {
    final name = TextEditingController(), phone = TextEditingController(), vat = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('عميل جديد'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'الجوال')),
        TextField(controller: vat, decoration: const InputDecoration(labelText: 'الرقم الضريبي (اختياري)')),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))],
    ));
    if (ok == true) {
      await CustomerService.save(Customer(id: const Uuid().v4(), name: name.text, phone: phone.text, vatNumber: vat.text.isEmpty ? null : vat.text));
      _refresh();
    }
  }



  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    body: RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(14), children: [
      const Text('قاعدة العملاء (B2B)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      if (_list.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا عملاء بعد'))),
      ..._list.map((c) => Card(margin: const EdgeInsets.symmetric(vertical: 4), child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(c.name),
        subtitle: Text('${c.phone} • ضريبي: ${c.vatNumber ?? '—'}'),
      ))),
    ])),
  );
}



/* ==========================================================
   28) دالة شاشة المزامنة والفروع (SyncScreen)
   ========================================================== */
/* ==========================================================
   28) دالة شاشة المزامنة والفروع (SyncScreen) — مصححة
   ========================================================== */
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncMode _mode = SyncMode.sameBranch;
  final _u = TextEditingController(), _p = TextEditingController(), _b = TextEditingController();
  bool _busy = false;



  Future<void> _register() async {
    setState(() => _busy = true);
    try {
      await SyncService.registerDevice(username: _u.text, password: _p.text, mode: _mode,
          newBranchName: _mode == SyncMode.newBranch ? (_b.text.isEmpty ? 'فرع جديد' : _b.text) : null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم تسجيل الجهاز وربط المزامنة')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
    setState(() => _busy = false);
  }



  Future<void> _syncNow() async {
    setState(() => _busy = true);
    await SyncService.sync();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔄 تمت المزامنة')));
  }



  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('حالة الجهاز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      Text('الفرع الحالي: ${SyncService.myBranch ?? Session.branchId}'),
      Text('التوكن: ${SyncService.token == null ? 'غير مسجل' : 'مفعّل'}'),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _busy ? null : _syncNow, icon: const Icon(Icons.sync), label: const Text('مزامنة الآن')),
    ]))),
    const SizedBox(height: 12),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('تسجيل جهاز/كاشير جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 10),
      TextField(controller: _u, decoration: const InputDecoration(labelText: 'اسم المستخدم (مدير)')),
      TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
      const SizedBox(height: 10),
      const Text('خيار المزامنة:'),
      RadioGroup<SyncMode>(
        groupValue: _mode,
        onChanged: (v) => setState(() => _mode = v ?? SyncMode.sameBranch),
        child: const Column(children: [
          RadioListTile<SyncMode>(contentPadding: EdgeInsets.zero, value: SyncMode.sameBranch,
              title: Text('نفس الفرع (مزامنة كاملة تشمل المخزون)')),
          RadioListTile<SyncMode>(contentPadding: EdgeInsets.zero, value: SyncMode.newBranch,
              title: Text('فرع جديد (كتالوج مشترك + مخزون مستقل)')),
        ]),
      ),
      if (_mode == SyncMode.newBranch)
        TextField(controller: _b, decoration: const InputDecoration(labelText: 'اسم الفرع الجديد')),
      const SizedBox(height: 10),
      FilledButton(onPressed: _busy ? null : _register, child: const Text('تسجيل الجهاز')),
    ]))),
  ]);
}


/* ==========================================================
   29) دالة شاشة الإعدادات الشاملة (SettingsScreen)
   ========================================================== */
/* ==========================================================
   29) دالة شاشة الإعدادات الشاملة (SettingsScreen) — مصححة
   ========================================================== */
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _shop = TextEditingController(), _vat = TextEditingController(), _rate = TextEditingController(text: '15');
  final _payUrl = TextEditingController(text: PaymentService.bridgeUrl);
  final _dIp = TextEditingController(text: DrawerService.ip);
  final _dPort = TextEditingController(text: '${DrawerService.port}');
  final _dUrl = TextEditingController(text: DrawerService.bridgeUrl);
  bool _recipes = true, _crm = true, _autoDrawer = true;
  String _payMode = 'simulate', _drawerMode = 'simulate';



  @override
  void initState() {
    super.initState();
    _load();
  }



  Future<void> _load() async {
    final s = await ShopSettings.get();
    _shop.text = s['shopName'] ?? '';
    _vat.text = s['vatNumber'] ?? '';
    _rate.text = '${s['taxRate'] ?? 15}';
    _recipes = s['recipesEnabled'] ?? true;
    _crm = s['crmEnabled'] ?? true;
    _payMode = s['payMode'] ?? 'simulate';
    _drawerMode = s['drawerMode'] ?? 'simulate';
    _autoDrawer = s['drawerAutoOpen'] ?? true;
    setState(() {});
  }



  Future<void> _save() async {
    await ShopSettings.save({
      'shopName': _shop.text, 'vatNumber': _vat.text,
      'taxRate': double.tryParse(_rate.text) ?? 15,
      'recipesEnabled': _recipes, 'crmEnabled': _crm,
      'payMode': _payMode, 'payBridgeUrl': _payUrl.text,
      'drawerMode': _drawerMode, 'drawerIp': _dIp.text,
      'drawerPort': int.tryParse(_dPort.text) ?? 9100,
      'drawerBridgeUrl': _dUrl.text, 'drawerAutoOpen': _autoDrawer,
    });
    await PaymentService.load();
    await DrawerService.load();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم حفظ الإعدادات')));
  }



  Future<void> _testDrawer() async {
    final ok = await DrawerService.open();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '🗄 فتح الدرج بنجاح' : '❌ فشل فتح الدرج')));
  }



  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🏪 المحل والضريبة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      TextField(controller: _shop, decoration: const InputDecoration(labelText: 'اسم المحل')),
      TextField(controller: _vat, decoration: const InputDecoration(labelText: 'الرقم الضريبي')),
      TextField(controller: _rate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نسبة الضريبة %')),
      SwitchListTile(value: _recipes, onChanged: (v) => setState(() => _recipes = v), title: const Text('تفعيل الوصفات وخصم المكونات (اختياري)')),
      SwitchListTile(value: _crm, onChanged: (v) => setState(() => _crm = v), title: const Text('تفعيل العملاء CRM (اختياري)')),
    ]))),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('💳 جهاز الدفع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const Text('طريقة الربط'),
      DropdownButton<String>(value: _payMode, isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'simulate', child: Text('محاكاة')),
            DropdownMenuItem(value: 'bridge', child: Text('جسر HTTP')),
          ],
          onChanged: (v) => setState(() => _payMode = v!)),
      TextField(controller: _payUrl, decoration: const InputDecoration(labelText: 'رابط الجسر')),
    ]))),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🗄 درج الكاشير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const Text('طريقة فتح الدرج'),
      DropdownButton<String>(value: _drawerMode, isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'simulate', child: Text('محاكاة')),
            DropdownMenuItem(value: 'escpos', child: Text('طابعة/درج ESC-POS عبر الشبكة')),
            DropdownMenuItem(value: 'bridge', child: Text('جسر HTTP')),
          ],
          onChanged: (v) => setState(() => _drawerMode = v!)),
      if (_drawerMode == 'escpos') ...[
        TextField(controller: _dIp, decoration: const InputDecoration(labelText: 'IP الطابعة/الدرج')),
        TextField(controller: _dPort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المنفذ (9100)')),
      ],
      if (_drawerMode == 'bridge') TextField(controller: _dUrl, decoration: const InputDecoration(labelText: 'رابط الجسر')),
      SwitchListTile(value: _autoDrawer, onChanged: (v) => setState(() => _autoDrawer = v), title: const Text('فتح تلقائي عند الدفع النقدي')),
      OutlinedButton.icon(onPressed: _testDrawer, icon: const Icon(Icons.door_sliding), label: const Text('اختبار فتح الدرج الآن')),
    ]))),
    const SizedBox(height: 8),
    FilledButton(onPressed: _save, child: const Text('💾 حفظ كل الإعدادات')),
    const SizedBox(height: 24),
  ]);
}
