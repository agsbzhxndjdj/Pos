import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'store.dart';
import 'models.dart';

/* ==========================================================
   9) دالة الجلسة الحالية (Session)
   ========================================================== */
class Session {
  static String userId = 'admin';
  static String userName = 'المدير';
  static String branchId = 'main';



  static Future<void> load() async {
    userId = await Store.metaGet('userId') ?? 'admin';
    userName = await Store.metaGet('userName') ?? 'المدير';
    branchId = await Store.metaGet('branch') ?? 'main';
  }



  static Future<void> save() async {
    await Store.metaSet('userId', userId);
    await Store.metaSet('userName', userName);
    await Store.metaSet('branch', branchId);
  }
}



/* ==========================================================
   10) دالة الضريبة: نظامي أو تعديل يدوي (TaxService)
   ========================================================== */
/* ==========================================================
   10) دالة الضريبة: نظامي أو تعديل يدوي (TaxService) — مصححة
   ========================================================== */
class TaxService {
  static Totals compute({required double gross, double discount = 0, double? manualTax, double rate = 15}) {
    final after = (gross - discount).clamp(0.0, double.infinity).toDouble();
    double tax, net;
    if (manualTax != null) { tax = manualTax.clamp(0.0, after).toDouble(); net = after - tax; }
    else { net = after / (1 + rate / 100); tax = after - net; }
    return Totals(gross: gross, discount: discount, net: net, tax: tax, total: after);
  }



  static void splitTaxToLines(List<InvoiceItem> items, double totalTax, double totalGross) {
    for (final it in items) {
      final share = totalGross == 0 ? 0.0 : it.gross / totalGross;
      it.tax = double.parse((totalTax * share).toStringAsFixed(2));
      it.net = double.parse((it.gross - it.tax).toStringAsFixed(2));
    }
  }
}



/* ==========================================================
   11) دالة الوصفات الاختيارية وخصم المكونات (RecipeService)
   ========================================================== */
class RecipeService {
  static Future<bool> globallyEnabled() async {
    final s = await Store.get('settings', 'global');
    return (s?.data['recipesEnabled'] ?? true) == true;
  }



  static Future<List<RecipeLine>> recipeOf(String productId) async =>
      (await Store.list('recipes')).where((r) => r.data['productId'] == productId).map((e) => RecipeLine.fromJson(e.data)).toList();



  static Future<bool> checkAvailability(String branchId, String productId, int qty) async {
    final p = (await Store.get('products', productId))?.data;
    if (p == null || p['hasRecipe'] != true || !await globallyEnabled()) return true;
    for (final r in await recipeOf(productId)) {
      final st = await Store.get('stock', '$branchId:${r.ingredientId}');
      final have = ((st?.data['qty'] as num?) ?? 0).toDouble();
      if (have < r.qty * qty) return false;
    }
    return true;
  }



  static Future<void> deduct(String branchId, String productId, int qty, {bool reverse = false}) async {
    final p = (await Store.get('products', productId))?.data;
    if (p == null || p['hasRecipe'] != true || !await globallyEnabled()) return;
    for (final r in await recipeOf(productId)) {
      final id = '$branchId:${r.ingredientId}';
      final cur = ((await Store.get('stock', id))?.data['qty'] as num?) ?? 0;
      final next = cur.toDouble() + (reverse ? r.qty * qty : -r.qty * qty);
      await Store.upsert('stock', id, Stock(branchId: branchId, ingredientId: r.ingredientId, qty: next).toJson());
    }
  }
}



/* ==========================================================
   12) دالة الورديات والعهدة النقدية (ShiftService)
   ========================================================== */
class ShiftReport {
  final double cashSales, cardSales, cashRefunds, cardRefunds, netSales, taxCollected, discountGiven;
  final int invoicesCount, refundsCount, deliveryCount;
  const ShiftReport({this.cashSales = 0, this.cardSales = 0, this.cashRefunds = 0, this.cardRefunds = 0,
      this.netSales = 0, this.taxCollected = 0, this.discountGiven = 0, this.invoicesCount = 0, this.refundsCount = 0, this.deliveryCount = 0});
  double get totalSales => cashSales + cardSales;
  double get netCollected => totalSales - cashRefunds - cardRefunds;
}



class ShiftService {
  static Future<Shift?> currentOpen(String userId) async =>
      (await Store.list('shifts')).map((e) => Shift.fromJson(e.data)).where((s) => s.userId == userId && s.status == 'open').firstOrNull;



  static Future<Shift> open(String userId, String branchId, double openingFloat) async {
    if (await currentOpen(userId) != null) throw Exception('لديك وردية مفتوحة بالفعل');
    final s = Shift(id: const Uuid().v4(), userId: userId, branchId: branchId,
        openedAt: DateTime.now().millisecondsSinceEpoch, openingFloat: openingFloat);
    await Store.upsert('shifts', s.id, s.toJson());
    return s;
  }



  static Future<ShiftReport> report(String shiftId) async {
    double cashSales = 0, cardSales = 0, cashRef = 0, cardRef = 0, net = 0, tax = 0, disc = 0;
    int inv = 0, ref = 0, del = 0;
    final invs = (await Store.list('invoices')).map((e) => Invoice.fromJson(e.data)).where((i) => i.shiftId == shiftId);
    for (final i in invs) {
      final cash = i.paymentMethod == 'cash';
      if (i.type == '388') {
        inv++;
        cash ? cashSales += i.total : cardSales += i.total;
        net += i.net; tax += i.tax; disc += i.discount;
        if (i.orderType == 'delivery') del++;
      } else {
        ref++;
        cash ? cashRef += i.total : cardRef += i.total;
        net -= i.net; tax -= i.tax;
      }
    }
    return ShiftReport(cashSales: cashSales, cardSales: cardSales, cashRefunds: cashRef, cardRefunds: cardRef,
        netSales: net, taxCollected: tax, discountGiven: disc, invoicesCount: inv, refundsCount: ref, deliveryCount: del);
  }



  static Future<double> expectedCash(Shift s) async {
    final r = await report(s.id);
    return s.openingFloat + r.cashSales - r.cashRefunds;
  }



  static Future<Shift> close(Shift s, double countedCash) async {
    s.expectedCash = await expectedCash(s);
    s.countedCash = countedCash;
    s.diff = countedCash - s.expectedCash;
    s.status = 'closed';
    s.closedAt = DateTime.now().millisecondsSinceEpoch;
    await Store.upsert('shifts', s.id, s.toJson());
    return s;
  }



  static Future<List<Shift>> history(String branchId, {int limit = 50}) async {
    final list = (await Store.list('shifts')).map((e) => Shift.fromJson(e.data)).where((s) => s.branchId == branchId).toList();
    list.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return list.take(limit).toList();
  }
}



/* ==========================================================
   13) دالة إعدادات المحل العامة (ShopSettings)
   ========================================================== */
class ShopSettings {
  static Map<String, dynamic> cache = {};



  static Future<Map<String, dynamic>> get() async {
    final s = (await Store.get('settings', 'global'))?.data;
    cache = s ?? {'taxRate': 15, 'recipesEnabled': true, 'crmEnabled': true, 'shopName': 'مخبز الخير', 'vatNumber': '300012345600003'};
    return cache;
  }



  static Future<void> save(Map<String, dynamic> v) async {
    cache = v;
    await Store.upsert('settings', 'global', v);
  }
}



/* ==========================================================
   14) دالة البيع وإتمام الفاتورة (PosService)
   ========================================================== */
class CartLine {
  String productId; int qty;
  CartLine(this.productId, this.qty);
}



class DeliveryRequest {
  String name, phone, address; double fee;
  DeliveryRequest({required this.name, required this.phone, required this.address, required this.fee});
}



class PosService {
  static Future<Invoice> checkout({
    required List<CartLine> cart,
    required String branchId,
    required String userId,
    required String paymentMethod,
    String? paymentRef,
    double discount = 0,
    double? manualTax,
    String? customerId,
    DeliveryRequest? delivery,
  }) async {
    final set = await ShopSettings.get();
    final rate = (set['taxRate'] as num?)?.toDouble() ?? 15;
    final shift = await ShiftService.currentOpen(userId);
    if (shift == null && paymentMethod == 'cash') throw Exception('افتح وردية أولاً قبل البيع النقدي');

    final items = <InvoiceItem>[];
    for (final l in cart) {
      final p = Product.fromJson((await Store.get('products', l.productId))!.data);
      if (!await RecipeService.checkAvailability(branchId, p.id, l.qty)) throw Exception('المخزون لا يكفي: ${p.name}');
      items.add(InvoiceItem(productId: p.id, name: p.name, qty: l.qty, unitPrice: p.price));
    }

    if (delivery != null) items.add(InvoiceItem(name: 'رسوم التوصيل', qty: 1, unitPrice: delivery.fee));

    final gross = items.fold(0.0, (s, i) => s + i.gross);
    final t = TaxService.compute(gross: gross, discount: discount, manualTax: manualTax, rate: rate);
    TaxService.splitTaxToLines(items, t.tax, t.gross);

    final inv = Invoice(
      id: const Uuid().v4(),
      number: 'INV-${DateTime.now().millisecondsSinceEpoch % 100000}',
      branchId: branchId, shiftId: shift?.id ?? 'no-shift', items: items,
      gross: t.gross, discount: t.discount, net: t.net, tax: t.tax, total: t.total,
      taxMode: manualTax != null ? 'manual' : 'standard',
      paymentMethod: paymentMethod, createdAt: DateTime.now().millisecondsSinceEpoch,
      orderType: delivery != null ? 'delivery' : 'takeaway',
    )..paymentRef = paymentRef..customerId = customerId;

    for (final l in cart) await RecipeService.deduct(branchId, l.productId, l.qty);

    if (delivery != null) {
      final dId = const Uuid().v4();
      await Store.upsert('deliveries', dId, DeliveryInfo(id: dId, invoiceId: inv.id, name: delivery.name,
          phone: delivery.phone, address: delivery.address, fee: delivery.fee, createdAt: inv.createdAt).toJson());
      inv.deliveryId = dId;
    }

    await Store.upsert('invoices', inv.id, inv.toJson());
    return inv;
  }
}



/* ==========================================================
   15) دالة المرتجعات والإشعار الدائن (RefundService)
   ========================================================== */
class RefundLine {
  String itemKey; int qty;
  RefundLine(this.itemKey, this.qty);
}



class RefundService {
  static int remaining(Invoice inv, String key) {
    final src = inv.items.where((i) => i.key == key).firstOrNull;
    if (src == null) return 0;
    return src.qty - (inv.refundedQty[key] ?? 0);
  }



  static Future<Invoice> createCreditNote({
    required String originalInvoiceId,
    required List<RefundLine> lines,
    required String reason,
  }) async {
    final origDoc = await Store.get('invoices', originalInvoiceId);
    if (origDoc == null) throw Exception('الفاتورة الأصلية غير موجودة');
    final orig = Invoice.fromJson(origDoc.data);
    final set = await ShopSettings.get();
    final rate = (set['taxRate'] as num?)?.toDouble() ?? 15;

    final items = <InvoiceItem>[];
    for (final l in lines.where((l) => l.qty > 0)) {
      final src = orig.items.where((i) => i.key == l.itemKey).firstOrNull;
      if (src == null || l.qty > remaining(orig, l.itemKey)) throw Exception('الكمية المرتجعة تتجاوز المباع');
      orig.refundedQty[l.itemKey] = (orig.refundedQty[l.itemKey] ?? 0) + l.qty;
      items.add(InvoiceItem(productId: src.productId, name: src.name, qty: l.qty, unitPrice: src.unitPrice));
      if (src.productId != null) await RecipeService.deduct(orig.branchId, src.productId!, l.qty, reverse: true);
    }
    if (items.isEmpty) throw Exception('لم تُحدد أي كمية للإرجاع');

    final gross = items.fold(0.0, (s, i) => s + i.gross);
    final manual = orig.taxMode == 'manual' && orig.gross > 0 ? (orig.tax * gross / orig.gross) : null;
    final t = TaxService.compute(gross: gross, manualTax: manual, rate: rate);
    TaxService.splitTaxToLines(items, t.tax, t.gross);

    final cn = Invoice(
      id: const Uuid().v4(), number: 'CN-${DateTime.now().millisecondsSinceEpoch % 100000}',
      branchId: orig.branchId, shiftId: orig.shiftId, items: items,
      gross: t.gross, discount: 0, net: t.net, tax: t.tax, total: t.total,
      taxMode: orig.taxMode, paymentMethod: orig.paymentMethod,
      createdAt: DateTime.now().millisecondsSinceEpoch, type: '381',
    )..originalUuid = orig.uuid ?? orig.id;

    orig.status = orig.items.every((i) => (orig.refundedQty[i.key] ?? 0) >= i.qty) ? 'refunded' : 'partially_refunded';
    await Store.upsert('invoices', orig.id, orig.toJson());
    await Store.upsert('invoices', cn.id, cn.toJson());
    await Store.upsert('refunds', cn.id, {'creditNoteId': cn.id, 'originalId': orig.id, 'reason': reason, 'at': cn.createdAt});
    return cn;
  }



  static Future<List<Invoice>> creditNotes() async =>
      (await Store.list('invoices')).map((e) => Invoice.fromJson(e.data)).where((i) => i.type == '381').toList();
}



/* ==========================================================
   16) دالة التوصيل الداخلي (DeliveryService)
   ========================================================== */
class DeliveryService {
  static Future<List<DeliveryInfo>> active() async {
    final list = (await Store.list('deliveries')).map((e) => DeliveryInfo.fromJson(e.data))
        .where((d) => d.status != 'delivered' && d.status != 'cancelled').toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }



  static Future<void> assignDriver(String id, String driver) async {
    final d = DeliveryInfo.fromJson((await Store.get('deliveries', id))!.data)..driver = driver..status = 'assigned';
    await Store.upsert('deliveries', id, d.toJson());
  }



  static Future<void> setStatus(String id, String status) async {
    final d = DeliveryInfo.fromJson((await Store.get('deliveries', id))!.data)..status = status;
    await Store.upsert('deliveries', id, d.toJson());
  }
}



/* ==========================================================
   17) دالة العملاء CRM الاختياري (CustomerService)
   ========================================================== */
class CustomerService {
  static Future<bool> enabled() async => (await ShopSettings.get())['crmEnabled'] == true;



  static Future<List<Customer>> all() async => (await Store.list('customers')).map((e) => Customer.fromJson(e.data)).toList();



  static Future<void> save(Customer c) => Store.upsert('customers', c.id, c.toJson());
}



/* ==========================================================
   18) دالة جهاز الدفع (PaymentService)
   ========================================================== */
class PaymentService {
  static String mode = 'simulate'; // simulate | bridge
  static String bridgeUrl = 'http://localhost:8888/api/pay';



  static Future<void> load() async {
    final s = await ShopSettings.get();
    mode = s['payMode'] ?? 'simulate';
    bridgeUrl = s['payBridgeUrl'] ?? bridgeUrl;
  }



  static Future<String?> charge(double amount, String invoice) async {
    if (mode == 'simulate') {
      await Future.delayed(const Duration(milliseconds: 1200));
      return 'SIM-${DateTime.now().millisecondsSinceEpoch}';
    }
    final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)))
        .post(bridgeUrl, data: {'amount': amount, 'currency': 'SAR', 'invoice': invoice});
    if (r.data['status'] == 'approved') return r.data['transaction_id']?.toString();
    throw Exception('رفض جهاز الدفع');
  }
}



/* ==========================================================
   19) دالة درج الكاشير Cash Drawer (DrawerService)
   ========================================================== */
class DrawerService {
  static String mode = 'simulate';   // simulate | escpos | bridge
  static String ip = '192.168.1.100';
  static int port = 9100;
  static String bridgeUrl = 'http://localhost:8888/api/drawer';
  static bool autoOpenOnCash = true;



  static Future<void> load() async {
    final s = await ShopSettings.get();
    mode = s['drawerMode'] ?? 'simulate';
    ip = s['drawerIp'] ?? ip;
    port = s['drawerPort'] ?? port;
    bridgeUrl = s['drawerBridgeUrl'] ?? bridgeUrl;
    autoOpenOnCash = s['drawerAutoOpen'] ?? true;
  }



  /// فتح درج الكاشير: ESC/POS عبر منفذ الطابعة، أو جسر HTTP، أو محاكاة
  static Future<bool> open() async {
    if (mode == 'escpos') {
      try {
        final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
        socket.add([27, 112, 0, 25, 250]); // أمر ESC p لفتح الدرج
        await socket.flush();
        socket.destroy();
        return true;
      } catch (e) {
        return false;
      }
    }


    if (mode == 'bridge') {
      try {
        await Dio(BaseOptions(connectTimeout: const Duration(seconds: 5))).post(bridgeUrl);
        return true;
      } catch (e) {
        return false;
      }
    }


    await Future.delayed(const Duration(milliseconds: 400));
    return true;
  }
}



/* ==========================================================
   20) دالة المزامنة والفروع (SyncService)
   ========================================================== */
class SyncService {
  static const baseUrl = 'http://YOUR_SERVER:8080';
  static final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 8)));
  static String? token, myBranch;
  static SyncMode mode = SyncMode.sameBranch;



  static Options get auth => Options(headers: {'Authorization': 'Bearer $token'});



  static Future<void> registerDevice({required String username, required String password,
      required SyncMode m, String? newBranchName}) async {
    final r = await dio.post('/register', data: {
      'username': username, 'password': password,
      'newBranch': m == SyncMode.newBranch, 'branchName': newBranchName,
    });
    token = r.data['token']; myBranch = r.data['branchId']; mode = m;
    Session.branchId = myBranch!;
    await Session.save();
    await Store.metaSet('token', token!);
    await Store.metaSet('branch', myBranch!);
    await Store.metaSet('mode', m.name);
  }



  static Future<void> sync() async {
    token ??= await Store.metaGet('token');
    myBranch ??= await Store.metaGet('branch');
    if (token == null) return;
    try {
      final since = int.parse(await Store.metaGet('lastSync') ?? '0');
      final local = await Store.changesSince(since);
      await dio.post('/sync/push', options: auth, data: {'docs': local.map((e) => e.toJson()).toList()});
      final r = await dio.post('/sync/pull', options: auth, data: {'since': since});
      await Store.applyRemote((r.data['docs'] as List).map((e) => Doc.fromJson(e)).toList());
      await Store.metaSet('lastSync', '${DateTime.now().millisecondsSinceEpoch}');
      await retryPendingZatca();
    } catch (_) {}
  }



  static Future<void> retryPendingZatca() async {
    for (final d in await Store.list('invoices')) {
      final inv = Invoice.fromJson(d.data);
      if (inv.zatca != null && inv.zatca!['status'] == 'accepted') continue;
      await issueZatca(inv);
    }
  }



  static Future<void> issueZatca(Invoice inv) async {
    if (token == null) return;
    try {
      final r = await dio.post(inv.type == '381' ? '/zatca/credit' : '/zatca/issue', options: auth, data: inv.toJson());
      inv.zatca = Map<String, dynamic>.from(r.data['zatca']);
      inv.uuid = inv.zatca!['uuid'];
      await Store.upsert('invoices', inv.id, inv.toJson());
    } catch (_) {}
  }
}



/* ==========================================================
   21) دالة منصات التوصيل جاهز/كيتا/نينجا (DeliveryAppsService)
   ========================================================== */
class DeliveryAppsService {
  static Future<void> pull() async {
    if (SyncService.token == null) return;
    try {
      final r = await SyncService.dio.post('/sync/pull', options: SyncService.auth,
          data: {'since': int.parse(await Store.metaGet('lastSync') ?? '0')});
      await Store.applyRemote((r.data['docs'] as List).map((e) => Doc.fromJson(e)).toList());
    } catch (_) {}
  }



  static Future<List<AppOrder>> list({List<String>? statuses}) async {
    var docs = (await Store.list('apporders')).map((e) => AppOrder.fromJson(e.data)).toList();
    if (statuses != null) docs = docs.where((o) => statuses.contains(o.status)).toList();
    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }



  static Future<int> pendingCount() async => (await list(statuses: ['new'])).length;



  static Future<Invoice?> accept(AppOrder o, String userId) async {
    await SyncService.dio.post('/apporders/ack', options: SyncService.auth,
        data: {'id': o.id, 'platform': o.platform, 'action': 'accept'});

    final cart = <CartLine>[];
    for (final it in o.items) {
      final all = (await Store.list('products')).map((e) => Product.fromJson(e.data));
      var p = all.where((p) => p.name.trim().toLowerCase() == it.name.trim().toLowerCase()).firstOrNull;
      if (p == null) {
        final catId = await _appsCategory();
        p = Product(id: const Uuid().v4(), name: it.name, price: it.price, categoryId: catId, hasRecipe: false);
        await Store.upsert('products', p.id, p.toJson());
      }
      cart.add(CartLine(p.id, it.qty));
    }

    final inv = await PosService.checkout(
      cart: cart,
      branchId: o.branchId.isNotEmpty ? o.branchId : (SyncService.myBranch ?? Session.branchId),
      userId: userId,
      paymentMethod: o.payment == 'cod' ? 'platform_cod' : 'platform_online',
      delivery: DeliveryRequest(name: o.customerName, phone: o.phone, address: o.address, fee: 0),
    );

    o.status = 'accepted'; o.posInvoiceId = inv.id;
    await Store.upsert('apporders', o.id, o.toJson());
    return inv;
  }



  static Future<void> reject(AppOrder o, String reason) async {
    await SyncService.dio.post('/apporders/ack', options: SyncService.auth,
        data: {'id': o.id, 'platform': o.platform, 'action': 'reject', 'reason': reason});
    o.status = 'rejected'; o.rejectReason = reason;
    await Store.upsert('apporders', o.id, o.toJson());
  }



  static Future<void> advance(AppOrder o, String status) async {
    o.status = status;
    await Store.upsert('apporders', o.id, o.toJson());
  }



  static Future<String> _appsCategory() async {
    final c = (await Store.list('categories')).where((c) => c.data['name'] == 'تطبيقات التوصيل').firstOrNull;
    if (c != null) return c.id;
    final id = const Uuid().v4();
    await Store.upsert('categories', id, Category(id: id, name: 'تطبيقات التوصيل').toJson());
    return id;
  }
}
