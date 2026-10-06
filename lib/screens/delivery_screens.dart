import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/services.dart';

/* ==========================================================
   25) دالة شاشة منصات التوصيل جاهز/كيتا/نينجا (DeliveryAppsScreen)
   ========================================================== */
class DeliveryAppsScreen extends StatefulWidget {
  final String userId;
  const DeliveryAppsScreen({super.key, required this.userId});
  @override
  State<DeliveryAppsScreen> createState() => _DeliveryAppsScreenState();
}

class _DeliveryAppsScreenState extends State<DeliveryAppsScreen> {
  List<AppOrder> _orders = [];
  Timer? _timer;
  bool _loading = true;



  static const _platformUi = {'jahez': ['🟢', 'جاهز'], 'keeta': ['🟡', 'كيتا'], 'ninja': ['🟣', 'نينجا']};
  static const _statusUi = {
    'new': ['طلب جديد', Color(0xFF0071E3)], 'accepted': ['مقبول', Color(0xFF34C759)],
    'preparing': ['قيد التجهيز', Color(0xFFFF9500)], 'ready': ['جاهز للاستلام', Color(0xFF5E5CE9)],
    'handover': ['سُلّم للسائق', Color(0xFF8E8E93)], 'delivered': ['تم التسليم', Color(0xFF34C759)],
    'rejected': ['مرفوض', Color(0xFFFF3B30)],
  };



  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }



  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }



  Future<void> _load() async {
    await DeliveryAppsService.pull();
    final orders = await DeliveryAppsService.list();
    if (mounted) setState(() { _orders = orders; _loading = false; });
  }



  Future<void> _accept(AppOrder o) async {
    try {
      final inv = await DeliveryAppsService.accept(o, widget.userId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ تم القبول وإنشاء الفاتورة ${inv?.number}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
    _load();
  }



  Future<void> _reject(AppOrder o) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('سبب الرفض'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'مثال: الصنف غير متوفر')),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('رفض الطلب'))],
    ));
    if (ok == true) { await DeliveryAppsService.reject(o, ctrl.text); _load(); }
  }



  String? _nextStatus(String s) => const {'accepted': 'preparing', 'preparing': 'ready', 'ready': 'handover', 'handover': 'delivered'}[s];



  String? _nextLabel(String s) => const {'accepted': 'بدء التجهيز', 'preparing': 'الطلب جاهز', 'ready': 'تسليم السائق', 'handover': 'تم التسليم'}[s];



  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final fresh = _orders.where((o) => o.status == 'new').toList();
    final active = _orders.where((o) => ['accepted', 'preparing', 'ready', 'handover'].contains(o.status)).toList();
    final done = _orders.where((o) => ['delivered', 'rejected'].contains(o.status)).toList();
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(14), children: [
      if (fresh.isNotEmpty) ...[_title('🔔 طلبات جديدة (${fresh.length})'), ...fresh.map((o) => _card(o, isNew: true))],
      if (active.isNotEmpty) ...[_title('🍳 قيد التنفيذ'), ...active.map((o) => _card(o))],
      if (done.isNotEmpty) ...[_title('🗄 المنتهية'), ...done.take(10).map((o) => _card(o))],
      if (_orders.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(40),
          child: Text('لا توجد طلبات من المنصات بعد\nبمجرد وصول طلب من جاهز/كيتا/نينجا سيظهر هنا فوراً', textAlign: TextAlign.center))),
    ]));
  }



  Widget _title(String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)));



  Widget _card(AppOrder o, {bool isNew = false}) {
    final p = _platformUi[o.platform] ?? ['📦', o.platform];
    final st = _statusUi[o.status] ?? [o.status, Colors.grey];
    return Card(margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: isNew ? const BorderSide(color: Color(0xFF0071E3), width: 2) : BorderSide.none),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(p[0])),
        title: Text('${p[1]} — #${o.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${o.customerName} • ${o.total.toStringAsFixed(2)} ر.س • ${o.payment == 'cod' ? 'دفع عند الاستلام' : 'مدفوع أونلاين'}'),
        trailing: Chip(label: Text(st[0] as String, style: TextStyle(color: st[1] as Color, fontSize: 11)),
            backgroundColor: (st[1] as Color).withValues(alpha: .12)),
        children: [
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...o.items.map((i) => Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [Text('${i.name} × ${i.qty}'), const Spacer(), Text((i.price * i.qty).toStringAsFixed(2))]))),
            const Divider(),
            Row(children: [const Text('الإجمالي'), const Spacer(), Text(o.total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))]),
            const SizedBox(height: 4),
            Text('📍 ${o.address} • 📞 ${o.phone}'),
            if (o.posInvoiceId != null) Text('🧾 فاتورة POS: ${o.posInvoiceId!.substring(0, 8)}…'),
            const SizedBox(height: 10),
            if (isNew) Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => _accept(o), icon: const Icon(Icons.check), label: const Text('قبول وإنشاء فاتورة'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => _reject(o),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red), icon: const Icon(Icons.close), label: const Text('رفض'))),
            ]) else if (_nextStatus(o.status) != null)
              SizedBox(width: double.infinity, child: FilledButton.tonal(
                  onPressed: () async { await DeliveryAppsService.advance(o, _nextStatus(o.status)!); _load(); },
                  child: Text(_nextLabel(o.status)!))),
          ])),
        ],
      ));
  }
}



/* ==========================================================
   26) دالة شاشة التوصيل الداخلي (InternalDeliveriesScreen)
   ========================================================== */
class InternalDeliveriesScreen extends StatefulWidget {
  const InternalDeliveriesScreen({super.key});
  @override
  State<InternalDeliveriesScreen> createState() => _InternalDeliveriesScreenState();
}

class _InternalDeliveriesScreenState extends State<InternalDeliveriesScreen> {
  List<DeliveryInfo> _list = [];



  @override
  void initState() {
    super.initState();
    _load();
  }



  Future<void> _load() async => setState(() => _list = []);



  Future<void> _refresh() async {
    final l = await DeliveryService.active();
    setState(() => _list = l);
  }



  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }



  static const _labels = {'pending': 'بانتظار سائق', 'assigned': 'مُسند لسائق', 'onWay': 'في الطريق', 'delivered': 'تم التسليم'};



  Future<void> _assign(DeliveryInfo d) async {
    final ctrl = TextEditingController(text: d.driver ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إسناد سائق'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'اسم السائق')),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إسناد'))],
    ));
    if (ok == true) { await DeliveryService.assignDriver(d.id, ctrl.text); _refresh(); }
  }



  Future<void> _advance(DeliveryInfo d) async {
    const flow = {'pending': 'assigned', 'assigned': 'onWay', 'onWay': 'delivered'};
    final next = flow[d.status];
    if (next == null) return;
    if (next == 'assigned') return _assign(d);
    await DeliveryService.setStatus(d.id, next);
    _refresh();
  }



  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(14), children: [
    const Text('طلبات التوصيل النشطة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    if (_list.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا توجد طلبات توصيل نشطة'))),
    ..._list.map((d) => Card(margin: const EdgeInsets.symmetric(vertical: 5), child: ListTile(
      leading: const Icon(Icons.two_wheeler),
      title: Text('${d.name} — ${d.phone}'),
      subtitle: Text('📍 ${d.address}\nسائق: ${d.driver ?? '—'} • الحالة: ${_labels[d.status] ?? d.status}'),
      trailing: FilledButton.tonal(onPressed: () => _advance(d),
          child: Text(d.status == 'pending' ? 'إسناد سائق' : d.status == 'assigned' ? 'خروج للتوصيل' : 'تم التسليم')),
    ))),
  ]));
}
