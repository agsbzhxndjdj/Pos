import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/store.dart';
import '../core/models.dart';
import '../core/services.dart';

/* ==========================================================
   22) دالة شاشة الكاشير نقطة البيع (PosScreen)
   ========================================================== */
class PosScreen extends StatefulWidget {
  final String branchId, userId;
  const PosScreen({super.key, required this.branchId, required this.userId});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Product> _products = [];
  List<Category> _categories = [];
  Map<String, bool> _available = {};
  Map<String, Product> _pById = {};
  final List<CartLine> _cart = [];
  String? _activeCat;
  double _discount = 0;
  double? _manualTax;
  String? _customerId;
  DeliveryRequest? _delivery;
  final _searchCtrl = TextEditingController();
  bool _loading = true;



  @override
  void initState() {
    super.initState();
    _boot();
  }



  Future<void> _boot() async {
    await _seedDemoIfEmpty();
    await _reload();
  }



  Future<void> _seedDemoIfEmpty() async {
    if ((await Store.list('products')).isNotEmpty) return;
    await ShopSettings.save({'taxRate': 15, 'recipesEnabled': true, 'crmEnabled': true,
        'shopName': 'مخبز الخير', 'vatNumber': '300012345600003'});
    final c1 = const Uuid().v4();
    await Store.upsert('categories', c1, Category(id: c1, name: 'مخبوزات').toJson());
    for (final n in ['تميس', 'ملوح', 'فطيرة جبنة']) {
      final p = Product(id: const Uuid().v4(), name: n, price: 10, categoryId: c1);
      await Store.upsert('products', p.id, p.toJson());
    }
  }



  Future<void> _reload() async {
    await ShopSettings.get();
    final docs = await Store.list('products');
    _products = docs.map((e) => Product.fromJson(e.data)).where((p) => p.active).toList();
    _pById = {for (final p in _products) p.id: p};
    _categories = (await Store.list('categories')).map((e) => Category.fromJson(e.data)).toList();
    _available = {};
    for (final p in _products) {
      _available[p.id] = await RecipeService.checkAvailability(widget.branchId, p.id, 1);
    }
    setState(() => _loading = false);
  }



  double get _rate => (ShopSettings.cache['taxRate'] as num?)?.toDouble() ?? 15;
  double get _gross => _cart.fold(0, (s, l) => s + (_pById[l.productId]?.price ?? 0) * l.qty);
  Totals get _totals => TaxService.compute(gross: _gross, discount: _discount, manualTax: _manualTax, rate: _rate);



  Future<void> _openDrawer() async {
    final ok = await DrawerService.open();
    _snack(ok ? '🗄 تم فتح درج الكاشير' : '❌ تعذر فتح الدرج — تحقق من الإعدادات/الاتصال');
  }



  Future<void> _add(String productId) async {
    final line = _cart.where((l) => l.productId == productId).firstOrNull;
    final newQty = (line?.qty ?? 0) + 1;
    if (!await RecipeService.checkAvailability(widget.branchId, productId, newQty)) {
      _snack('🚨 المخزون لا يكفي'); return;
    }
    setState(() { if (line != null) line.qty = newQty; else _cart.add(CartLine(productId, 1)); });
  }



  Future<void> _setQty(String productId, int qty) async {
    if (qty <= 0) { setState(() => _cart.removeWhere((l) => l.productId == productId)); return; }
    if (!await RecipeService.checkAvailability(widget.branchId, productId, qty)) {
      _snack('🚨 كمية غير كافية'); return;
    }
    setState(() => _cart.firstWhere((l) => l.productId == productId).qty = qty);
  }



  Future<void> _editTax() async {
    final t = _totals;
    final ctrl = TextEditingController(text: (_manualTax ?? t.tax).toStringAsFixed(2));
    final res = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('ضريبة الفاتورة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('الوضع النظامي: ${t.tax.toStringAsFixed(2)} ر.س'),
        const SizedBox(height: 8),
        TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'مبلغ الضريبة يدوياً')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('إعادة للنظامي')),
        FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? -1), child: const Text('تطبيق يدوي')),
      ],
    ));
    if (res == null) return;
    setState(() => _manualTax = res < 0 ? null : res.clamp(0, _totals.total).toDouble());
  }



  Future<void> _editDiscount() async {
    final ctrl = TextEditingController(text: _discount.toStringAsFixed(2));
    final v = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('الخصم'),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0), child: const Text('تطبيق'))],
    ));
    if (v != null) setState(() => _discount = v.clamp(0, _gross).toDouble());
  }



  Future<void> _pickCustomer() async {
    if (!await CustomerService.enabled()) { _snack('CRM معطل من الإعدادات'); return; }
    final customers = await CustomerService.all();
    final picked = await showDialog<Customer>(context: context, builder: (ctx) => SimpleDialog(
      title: const Text('اختيار عميل (B2B)'),
      children: [
        ...customers.map((c) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c), child: Text('${c.name} — ${c.phone}'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx, Customer(id: '', name: '', phone: '')), child: const Text('➕ عميل جديد')),
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx), child: const Text('❌ بدون عميل')),
      ],
    ));
    if (picked == null) return;
    if (picked.id.isEmpty) {
      final c = await _newCustomerDialog();
      if (c == null) return;
      await CustomerService.save(c);
      setState(() => _customerId = c.id);
    } else setState(() => _customerId = picked.id);
  }



  Future<Customer?> _newCustomerDialog() async {
    final name = TextEditingController(), phone = TextEditingController(), vat = TextEditingController();
    return showDialog<Customer>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('عميل جديد'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'الجوال')),
        TextField(controller: vat, decoration: const InputDecoration(labelText: 'الرقم الضريبي (اختياري)')),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx,
          Customer(id: const Uuid().v4(), name: name.text, phone: phone.text, vatNumber: vat.text.isEmpty ? null : vat.text)),
          child: const Text('حفظ'))],
    ));
  }



  Future<void> _editDelivery() async {
    final name = TextEditingController(text: _delivery?.name ?? '');
    final phone = TextEditingController(text: _delivery?.phone ?? '');
    final address = TextEditingController(text: _delivery?.address ?? '');
    final fee = TextEditingController(text: (_delivery?.fee ?? 10).toString());
    final res = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text(' طلب توصيل'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم العميل')),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'الجوال')),
        TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
        TextField(controller: fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رسوم التوصيل')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء التوصيل')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
      ],
    ));
    setState(() {
      if (res == true) _delivery = DeliveryRequest(name: name.text, phone: phone.text, address: address.text, fee: double.tryParse(fee.text) ?? 0);
      else if (res == false) _delivery = null;
    });
  }



  Future<bool> _ensureShift() async {
    if (await ShiftService.currentOpen(widget.userId) != null) return true;
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('💰 افتح وردية أولاً'),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'العهدة النقدية بداية الوردية')),
      actions: [FilledButton(onPressed: () async {
        await ShiftService.open(widget.userId, widget.branchId, double.tryParse(ctrl.text) ?? 0);
        Navigator.pop(ctx, true);
      }, child: const Text('فتح الوردية'))],
    ));
    return ok == true;
  }



  Future<void> _pay(String method) async {
    if (_cart.isEmpty) { _snack('السلة فارغة'); return; }
    if (method == 'cash' && !await _ensureShift()) return;
    final t = _totals;
    String? payRef;
    if (method == 'card') {
      try { payRef = await PaymentService.charge(t.total, 'PRE-${DateTime.now().millisecondsSinceEpoch % 99999}'); }
      catch (e) { _snack('❌ $e'); return; }
    }
    try {
      final inv = await PosService.checkout(
        cart: _cart, branchId: widget.branchId, userId: widget.userId,
        paymentMethod: method, paymentRef: payRef, discount: _discount,
        manualTax: _manualTax, customerId: _customerId, delivery: _delivery,
      );
      await SyncService.issueZatca(inv);
      if (method == 'cash' && DrawerService.autoOpenOnCash) await DrawerService.open();
      setState(() { _cart.clear(); _discount = 0; _manualTax = null; _customerId = null; _delivery = null; });
      await _reload();
      if (mounted) await _showReceipt(inv);
      SyncService.sync();
    } catch (e) { _snack('❌ $e'); }
  }



  Future<void> _showReceipt(Invoice inv) => showDialog(context: context, builder: (ctx) => AlertDialog(
    title: Text('فاتورة ${inv.number}'),
    content: SizedBox(width: 320, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ...inv.items.map((i) => Padding(padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [Expanded(child: Text('${i.name} × ${i.qty}')), Text((i.unitPrice * i.qty).toStringAsFixed(2))]))),
      const Divider(),
      Row(children: [const Text('قبل الضريبة'), const Spacer(), Text(inv.net.toStringAsFixed(2))]),
      Row(children: [Text('الضريبة ${inv.taxMode == 'manual' ? '(يدوي)' : ''}'), const Spacer(), Text(inv.tax.toStringAsFixed(2))]),
      Row(children: [const Text('الإجمالي'), const Spacer(), Text(inv.total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))]),
      if (inv.zatca?['qr'] != null) ...[
        const SizedBox(height: 12),
        QrImageView(data: inv.zatca!['qr'], size: 150),
        Text('ZATCA: ${inv.zatca!['status']}'),
      ],
    ]))),
    actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم'))],
  ));



  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));



  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (ctx, c) {
      final wide = c.maxWidth >= 900;
      return Scaffold(
        appBar: AppBar(title: const Text('نقطة البيع'), actions: [
          IconButton(icon: const Icon(Icons.door_sliding), tooltip: 'فتح درج الكاشير', onPressed: _openDrawer),
        ]),
        floatingActionButton: wide ? null : FloatingActionButton.extended(
          onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true,
              builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * .82, child: _buildCart(ctx))),
          icon: const Icon(Icons.shopping_cart),
          label: Text('${_totals.total.toStringAsFixed(2)} ر.س')),
        body: Row(children: [
          Expanded(child: _buildProducts(ctx)),
          if (wide) SizedBox(width: 380, child: _buildCart(ctx)),
        ]),
      );
    });
  }



  Widget _buildProducts(BuildContext context) {
    final parents = _categories.where((c) => c.parentId == null);
    final list = _activeCat == null ? _products : _products.where((p) {
      final subs = _categories.where((c) => c.parentId == _activeCat).map((c) => c.id);
      return p.categoryId == _activeCat || subs.contains(p.categoryId);
    }).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(10), child: TextField(controller: _searchCtrl,
        onSubmitted: (v) async {
          final p = _products.where((p) => p.barcode == v || p.name == v).firstOrNull;
          if (p != null) { await _add(p.id); _searchCtrl.clear(); } else _snack('❌ غير موجود');
        },
        decoration: InputDecoration(hintText: '🔍 ابحث أو امسح الباركود ثم Enter', isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30))))),
      SizedBox(height: 46, child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), scrollDirection: Axis.horizontal, children: [
        _chip('الكل', _activeCat == null, () => setState(() => _activeCat = null)),
        for (final c in parents) ...[
          _chip(c.name, _activeCat == c.id, () => setState(() => _activeCat = c.id)),
          for (final s in _categories.where((x) => x.parentId == c.id))
            _chip('↳ ${s.name}', _activeCat == s.id, () => setState(() => _activeCat = s.id)),
        ],
      ])),
      Expanded(child: GridView.builder(padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, childAspectRatio: .85, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final p = list[i]; final ok = _available[p.id] ?? true;
          return Opacity(opacity: ok ? 1 : .45, child: Card(clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: ok ? () => _add(p.id) : null,
              child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Container(width: double.infinity, alignment: Alignment.center,
                    decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                    child: const Text('🥐', style: TextStyle(fontSize: 34)))),
                const SizedBox(height: 6),
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  Text('${p.price.toStringAsFixed(2)} ر.س', style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: (ok ? Colors.green : Colors.red).withOpacity(.15)),
                      child: Text(ok ? 'متوفر' : 'نفد', style: TextStyle(fontSize: 10, color: ok ? Colors.green.shade700 : Colors.red))),
                ]),
              ])))));
        })),
    ]);
  }



  Widget _chip(String t, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: FilterChip(label: Text(t), selected: active, onSelected: (_) => onTap()));



  Widget _buildCart(BuildContext context) {
    final t = _totals;
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Icon(Icons.receipt_long), const SizedBox(width: 8),
        const Text('الفاتورة الحالية', style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.person), tooltip: 'عميل', onPressed: _pickCustomer),
        IconButton(icon: Icon(_delivery != null ? Icons.delivery_dining : Icons.local_shipping), tooltip: 'توصيل', onPressed: _editDelivery),
        IconButton(icon: const Icon(Icons.door_sliding), tooltip: 'فتح الدرج', onPressed: _openDrawer),
      ])),
      Expanded(child: _cart.isEmpty
        ? const Center(child: Text('السلة فارغة'))
        : ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            for (final l in _cart) Card(margin: const EdgeInsets.symmetric(vertical: 4), child: ListTile(
              dense: true, title: Text(_pById[l.productId]?.name ?? ''),
              subtitle: Text('${(_pById[l.productId]?.price ?? 0).toStringAsFixed(2)} × ${l.qty}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _setQty(l.productId, l.qty - 1)),
                Text('${l.qty}', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _setQty(l.productId, l.qty + 1)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _setQty(l.productId, 0)),
              ]))),
          ])),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cs.surfaceContainerHighest.withOpacity(.4)), child: Column(children: [
        Row(children: [const Text('قبل الضريبة'), const Spacer(), Text(t.net.toStringAsFixed(2))]),
        Row(children: [
          Text('الضريبة (${_manualTax != null ? 'يدوي' : 'نظامي ${_rate}%'})'),
          IconButton(icon: const Icon(Icons.edit, size: 16), tooltip: 'تعديل يدوي', onPressed: _editTax),
          const Spacer(), Text(t.tax.toStringAsFixed(2))]),
        Row(children: [const Text('الخصم'), const Spacer(),
          InkWell(onTap: _editDiscount, child: Text(t.discount.toStringAsFixed(2), style: const TextStyle(decoration: TextDecoration.underline)))]),
        const Divider(),
        Row(children: [const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)), const Spacer(),
          Text(t.total.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: cs.primary))]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: FilledButton.tonalIcon(onPressed: () { setState(() { _cart.clear(); _discount = 0; _manualTax = null; }); },
              icon: const Icon(Icons.delete_sweep, size: 18), label: const Text('إلغاء'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => _pay('cash'), child: const Text('💵 نقدي'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: () => _pay('card'), child: const Text('💳 جهاز الدفع'))),
        ]),
      ])),
    ]);
  }
}
