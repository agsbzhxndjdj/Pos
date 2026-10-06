import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/store.dart';
import '../core/models.dart';
import '../core/services.dart';

/* ==========================================================
   24) دالة شاشة المرتجعات والإشعارات الدائنة (RefundsScreen)
   ========================================================== */
class RefundsScreen extends StatefulWidget {
  final String userId, branchId;
  const RefundsScreen({super.key, required this.userId, required this.branchId});
  @override
  State<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends State<RefundsScreen> {
  List<Invoice> _refundable = [];
  List<Invoice> _credits = [];
  bool _loading = true;



  @override
  void initState() {
    super.initState();
    _load();
  }



  Future<void> _load() async {
    setState(() => _loading = true);
    final all = (await Store.list('invoices')).map((e) => Invoice.fromJson(e.data)).toList();
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _refundable = all.where((i) => i.type == '388' && i.status != 'refunded').toList();
    _credits = all.where((i) => i.type == '381').toList();
    setState(() => _loading = false);
  }



  static String dt(int ms) => DateFormat('yyyy/MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));



  Future<void> _refundDialog(Invoice inv) async {
    final qty = <String, int>{for (final i in inv.items) i.key: 0};
    final reason = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: Text('إرجاع من فاتورة ${inv.number}'),
      content: SizedBox(width: 340, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final i in inv.items)
          ListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: Text('${i.name} (متبقي ${RefundService.remaining(inv, i.key)})'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setS(() => qty[i.key] = ((qty[i.key] ?? 0) - 1).clamp(0, RefundService.remaining(inv, i.key)))),
              Text('${qty[i.key] ?? 0}'),
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setS(() => qty[i.key] = ((qty[i.key] ?? 0) + 1).clamp(0, RefundService.remaining(inv, i.key)))),
            ])),
        TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب الإرجاع')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إصدار إشعار دائن')),
      ],
    )));
    if (ok != true) return;
    try {
      final cn = await RefundService.createCreditNote(
        originalInvoiceId: inv.id,
        lines: qty.entries.map((e) => RefundLine(e.key, e.value)).toList(),
        reason: reason.text,
      );
      await SyncService.issueZatca(cn);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ صدر الإشعار الدائن ${cn.number} بمبلغ ${cn.total.toStringAsFixed(2)} ر.س')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
    await _load();
  }



  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(14), children: [
      const Text('فواتير قابلة للإرجاع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ..._refundable.take(30).map((i) => Card(margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          title: Text('${i.number} — ${i.total.toStringAsFixed(2)} ر.س'),
          subtitle: Text('${dt(i.createdAt)} • ${i.status == 'partially_refunded' ? 'مرجعة جزئياً' : 'مدفوعة'}'),
          trailing: FilledButton.tonal(onPressed: () => _refundDialog(i), child: const Text('إرجاع')),
        ))),
      const SizedBox(height: 16),
      const Text('الإشعارات الدائنة الصادرة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ..._credits.map((c) => Card(margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: const Icon(Icons.assignment_return),
          title: Text('${c.number} — ${c.total.toStringAsFixed(2)} ر.س'),
          subtitle: Text('مرتبطة بالفاتورة: ${c.originalUuid ?? '-'} • ${dt(c.createdAt)}'),
        ))),
    ]);
  }
}
