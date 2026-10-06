import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/store.dart';
import '../core/models.dart';
import '../core/services.dart';

/* ==========================================================
   23) دالة شاشة الورديات والعهدة (ShiftsScreen)
   ========================================================== */
class ShiftsScreen extends StatefulWidget {
  final String userId, branchId;
  const ShiftsScreen({super.key, required this.userId, required this.branchId});
  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  Shift? _open;
  ShiftReport? _live;
  List<Shift> _history = [];
  Map<String, String> _userNames = {};
  bool _loading = true;



  static String money(double v) => '${v.toStringAsFixed(2)} ر.س';



  static String dt(int ms) => DateFormat('yyyy/MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));



  @override
  void initState() {
    super.initState();
    _load();
  }



  Future<void> _load() async {
    setState(() => _loading = true);
    _open = await ShiftService.currentOpen(widget.userId);
    if (_open != null) _live = await ShiftService.report(_open!.id);
    _history = await ShiftService.history(widget.branchId);
    _userNames = {for (final u in await Store.list('users')) u.id: (u.data['name'] ?? '') as String};
    setState(() => _loading = false);
  }



  String _nameOf(Shift s) => _userNames[s.userId]?.isNotEmpty == true ? _userNames[s.userId]! : s.userId.substring(0, 6);



  Future<void> _openShift() async {
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('💰 فتح وردية جديدة'),
      content: TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true, decoration: const InputDecoration(labelText: 'العهدة الافتتاحية')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('فتح الوردية')),
      ],
    ));
    if (ok != true) return;
    try {
      await ShiftService.open(widget.userId, widget.branchId, double.tryParse(ctrl.text) ?? 0);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
    await _load();
  }



  Future<void> _closeShift(Shift s) async {
    final r = await ShiftService.report(s.id);
    final expected = s.openingFloat + r.cashSales - r.cashRefunds;
    final ctrl = TextEditingController();
    final closed = await showDialog<Shift>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final counted = double.tryParse(ctrl.text);
      final diff = counted == null ? null : counted - expected;
      return AlertDialog(
        title: const Text('🔒 تصفية الوردية'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row('العهدة الافتتاحية', money(s.openingFloat)),
          _row('مبيعات نقدية', money(r.cashSales)),
          _row('مرتجعات نقدية', '- ${money(r.cashRefunds)}'),
          const Divider(),
          _row('النقد المتوقع بالدرج', money(expected), bold: true),
          const SizedBox(height: 10),
          TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true, decoration: const InputDecoration(labelText: 'النقد المعدود فعلياً'), onChanged: (_) => setS(() {})),
          if (diff != null)
            Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                    color: (diff == 0 ? Colors.green : diff > 0 ? Colors.orange : Colors.red).withOpacity(.12)),
                child: Row(children: [
                  Text(diff == 0 ? '✅ مطابق' : diff > 0 ? '📈 زيادة' : '📉 عجز', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(), Text(money(diff.abs()), style: const TextStyle(fontWeight: FontWeight.bold)),
                ])),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
          FilledButton(onPressed: () async {
            final c = double.tryParse(ctrl.text);
            if (c == null) return;
            Navigator.pop(ctx, await ShiftService.close(s, c));
          }, child: const Text('إغلاق الوردية')),
        ],
      );
    }));
    if (closed == null) return;
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('نتيجة التصفية'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _row('المتوقع', money(closed.expectedCash)),
        _row('المعدود', money(closed.countedCash)),
        _row('الفرق', money(closed.diff), bold: true),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم'))],
    ));
    await _load();
  }



  Future<void> _reportSheet(Shift s) async {
    final r = await ShiftService.report(s.id);
    if (!mounted) return;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Text('تقرير وردية ${_nameOf(s)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
        const SizedBox(height: 14),
        _row('عدد الفواتير', '${r.invoicesCount}'),
        _row('عدد المرتجعات', '${r.refundsCount}'),
        _row('طلبات التوصيل', '${r.deliveryCount}'),
        const Divider(),
        _row('مبيعات نقدية', money(r.cashSales)),
        _row('مبيعات بطاقة', money(r.cardSales)),
        _row('إجمالي المبيعات', money(r.totalSales), bold: true),
        _row('صافي المحصل', money(r.netCollected), bold: true),
        const Divider(),
        _row('المبيعات قبل الضريبة', money(r.netSales)),
        _row('الضريبة المحصلة', money(r.taxCollected)),
        _row('الخصومات', money(r.discountGiven)),
        const Divider(),
        _row('العهدة الافتتاحية', money(s.openingFloat)),
        if (s.status == 'closed') ...[
          _row('النقد المعدود', money(s.countedCash)),
          _row('الفرق', money(s.diff), bold: true),
        ],
        const SizedBox(height: 20),
      ])),
    ));
  }



  Widget _row(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(l, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      const Spacer(),
      Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    ]));



  Widget _diffChip(Shift s) {
    if (s.status == 'open') return const Chip(label: Text('مفتوحة'));
    final c = s.diff == 0 ? Colors.green : s.diff > 0 ? Colors.orange : Colors.red;
    final t = s.diff == 0 ? 'مطابقة' : '${s.diff > 0 ? 'زيادة' : 'عجز'} ${money(s.diff.abs())}';
    return Chip(label: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11)),
        backgroundColor: c.withValues(alpha: .12));
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(14), children: [
      if (_open != null && _live != null)
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.badge, size: 28), const SizedBox(width: 8),
            const Text('الوردية الحالية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const Spacer(), _diffChip(_open!),
          ]),
          const SizedBox(height: 6),
          Text('بدأت: ${dt(_open!.openedAt)}'),
          const Divider(height: 20),
          _row('العهدة الافتتاحية', money(_open!.openingFloat)),
          _row('مبيعات نقدية حتى الآن', money(_live!.cashSales)),
          _row('النقد المتوقع بالدرج', money(_open!.openingFloat + _live!.cashSales - _live!.cashRefunds), bold: true),
          _row('إجمالي مبيعات الوردية', money(_live!.totalSales), bold: true),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _reportSheet(_open!), icon: const Icon(Icons.summarize), label: const Text('تقرير مفصل'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: () => _closeShift(_open!),
                style: FilledButton.styleFrom(backgroundColor: cs.error), icon: const Icon(Icons.lock_clock), label: const Text('إغلاق وتصفية'))),
          ]),
        ])))
      else
        Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(children: [
          const Icon(Icons.lock_open, size: 46),
          const SizedBox(height: 8),
          const Text('لا توجد وردية مفتوحة', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _openShift, icon: const Icon(Icons.add), label: const Text('فتح وردية جديدة')),
        ])))),
      const SizedBox(height: 10),
      const Text('سجل الورديات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ..._history.map((s) => Card(margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: CircleAvatar(child: Text(_nameOf(s).substring(0, 1))),
          title: Text('${_nameOf(s)} — ${dt(s.openedAt)}'),
          subtitle: Text(s.status == 'open' ? 'مستمرّة…' : 'أُغلقت ${dt(s.closedAt!)}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _diffChip(s),
            IconButton(icon: const Icon(Icons.summarize_outlined), tooltip: 'تقرير', onPressed: () => _reportSheet(s)),
          ]),
        ))),
    ]));
  }
}
