/* ==========================================================
   7) دالة نماذج البيانات الأساسية (Models)
   ========================================================== */
enum Role { admin, cashier }
enum TaxMode { standard, manual }
enum OrderType { dineIn, takeaway, delivery }
enum DeliveryStatus { pending, assigned, onWay, delivered, cancelled }
enum SyncMode { sameBranch, newBranch }



class Category {
  String id, name; String? parentId;
  Category({required this.id, required this.name, this.parentId});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'parentId': parentId};
  factory Category.fromJson(Map j) => Category(id: j['id'], name: j['name'], parentId: j['parentId']);
}



class Product {
  String id, name, barcode; String? categoryId; double price; bool hasRecipe, active;
  Product({required this.id, required this.name, required this.price, this.categoryId, this.barcode = '', this.hasRecipe = false, this.active = true});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'categoryId': categoryId, 'price': price, 'barcode': barcode, 'hasRecipe': hasRecipe, 'active': active};
  factory Product.fromJson(Map j) => Product(id: j['id'], name: j['name'], categoryId: j['categoryId'],
      price: (j['price'] as num).toDouble(), barcode: j['barcode'] ?? '', hasRecipe: j['hasRecipe'] ?? false, active: j['active'] ?? true);
}



class Ingredient {
  String id, name, unit; double minAlert;
  Ingredient({required this.id, required this.name, required this.unit, this.minAlert = 0});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'unit': unit, 'minAlert': minAlert};
  factory Ingredient.fromJson(Map j) => Ingredient(id: j['id'], name: j['name'], unit: j['unit'], minAlert: (j['minAlert'] as num?)?.toDouble() ?? 0);
}



class Stock {
  String branchId, ingredientId; double qty;
  Stock({required this.branchId, required this.ingredientId, this.qty = 0});
  Map<String, dynamic> toJson() => {'branchId': branchId, 'ingredientId': ingredientId, 'qty': qty};
  factory Stock.fromJson(Map j) => Stock(branchId: j['branchId'], ingredientId: j['ingredientId'], qty: (j['qty'] as num).toDouble());
}



class RecipeLine {
  String id, productId, ingredientId; double qty;
  RecipeLine({required this.id, required this.productId, required this.ingredientId, required this.qty});
  Map<String, dynamic> toJson() => {'id': id, 'productId': productId, 'ingredientId': ingredientId, 'qty': qty};
  factory RecipeLine.fromJson(Map j) => RecipeLine(id: j['id'], productId: j['productId'], ingredientId: j['ingredientId'], qty: (j['qty'] as num).toDouble());
}



class Customer {
  String id, name, phone; String? vatNumber;
  Customer({required this.id, required this.name, required this.phone, this.vatNumber});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'vatNumber': vatNumber};
  factory Customer.fromJson(Map j) => Customer(id: j['id'], name: j['name'], phone: j['phone'], vatNumber: j['vatNumber']);
}



class Shift {
  String id, userId, branchId; int openedAt; int? closedAt;
  double openingFloat, countedCash, expectedCash, diff; String status;
  Shift({required this.id, required this.userId, required this.branchId, required this.openedAt,
      this.openingFloat = 0, this.countedCash = 0, this.expectedCash = 0, this.diff = 0, this.status = 'open', this.closedAt});
  Map<String, dynamic> toJson() => {'id': id, 'userId': userId, 'branchId': branchId, 'openedAt': openedAt, 'closedAt': closedAt,
      'openingFloat': openingFloat, 'countedCash': countedCash, 'expectedCash': expectedCash, 'diff': diff, 'status': status};
  factory Shift.fromJson(Map j) => Shift(id: j['id'], userId: j['userId'], branchId: j['branchId'], openedAt: j['openedAt'],
      closedAt: j['closedAt'], openingFloat: (j['openingFloat'] as num).toDouble(), countedCash: (j['countedCash'] as num).toDouble(),
      expectedCash: (j['expectedCash'] as num).toDouble(), diff: (j['diff'] as num).toDouble(), status: j['status']);
}



class DeliveryInfo {
  String id, invoiceId, name, phone, address; double fee; String? driver; String status; int createdAt;
  DeliveryInfo({required this.id, required this.invoiceId, required this.name, required this.phone,
      required this.address, required this.fee, this.driver, this.status = 'pending', required this.createdAt});
  Map<String, dynamic> toJson() => {'id': id, 'invoiceId': invoiceId, 'name': name, 'phone': phone,
      'address': address, 'fee': fee, 'driver': driver, 'status': status, 'createdAt': createdAt};
  factory DeliveryInfo.fromJson(Map j) => DeliveryInfo(id: j['id'], invoiceId: j['invoiceId'], name: j['name'],
      phone: j['phone'], address: j['address'], fee: (j['fee'] as num).toDouble(), driver: j['driver'], status: j['status'], createdAt: j['createdAt']);
}



class InvoiceItem {
  String? productId; String name; int qty; double unitPrice, net, tax;
  InvoiceItem({this.productId, required this.name, required this.qty, required this.unitPrice, this.net = 0, this.tax = 0});
  double get gross => unitPrice * qty;
  String get key => productId ?? name;
  Map<String, dynamic> toJson() => {'productId': productId, 'name': name, 'qty': qty, 'unitPrice': unitPrice, 'net': net, 'tax': tax};
  factory InvoiceItem.fromJson(Map j) => InvoiceItem(productId: j['productId'], name: j['name'], qty: j['qty'],
      unitPrice: (j['unitPrice'] as num).toDouble(), net: (j['net'] as num?)?.toDouble() ?? 0, tax: (j['tax'] as num?)?.toDouble() ?? 0);
}



class Invoice {
  String id, number, branchId, shiftId; String? uuid, customerId, deliveryId, originalUuid, paymentRef;
  String type, orderType, taxMode, paymentMethod, status;
  List<InvoiceItem> items;
  double gross, discount, net, tax, total;
  int createdAt;
  Map<String, dynamic>? zatca;
  Map<String, int> refundedQty;
  Invoice({required this.id, required this.number, required this.branchId, required this.shiftId, required this.items,
      required this.gross, required this.discount, required this.net, required this.tax, required this.total,
      required this.taxMode, required this.paymentMethod, required this.createdAt,
      this.type = '388', this.orderType = 'takeaway', this.status = 'paid', this.refundedQty = const {}});
  Map<String, dynamic> toJson() => {'id': id, 'number': number, 'branchId': branchId, 'shiftId': shiftId, 'uuid': uuid,
      'customerId': customerId, 'deliveryId': deliveryId, 'originalUuid': originalUuid, 'paymentRef': paymentRef,
      'type': type, 'orderType': orderType, 'items': items.map((e) => e.toJson()).toList(), 'gross': gross, 'discount': discount,
      'net': net, 'tax': tax, 'total': total, 'taxMode': taxMode, 'paymentMethod': paymentMethod, 'status': status,
      'createdAt': createdAt, 'zatca': zatca, 'refundedQty': refundedQty};
  factory Invoice.fromJson(Map j) => Invoice(id: j['id'], number: j['number'], branchId: j['branchId'], shiftId: j['shiftId'],
      items: (j['items'] as List).map((e) => InvoiceItem.fromJson(e)).toList(), gross: (j['gross'] as num).toDouble(),
      discount: (j['discount'] as num).toDouble(), net: (j['net'] as num).toDouble(), tax: (j['tax'] as num).toDouble(),
      total: (j['total'] as num).toDouble(), taxMode: j['taxMode'], paymentMethod: j['paymentMethod'], createdAt: j['createdAt'],
      type: j['type'] ?? '388', orderType: j['orderType'] ?? 'takeaway', status: j['status'] ?? 'paid',
      refundedQty: Map<String, int>.from(j['refundedQty'] ?? {}))
    ..uuid = j['uuid'] ..customerId = j['customerId'] ..deliveryId = j['deliveryId']
    ..originalUuid = j['originalUuid'] ..paymentRef = j['paymentRef']
    ..zatca = (j['zatca'] as Map?)?.cast<String, dynamic>();
}



/* ==========================================================
   8) دالة نموذج طلبات منصات التوصيل (AppOrder)
   ========================================================== */
class AppItemView {
  final String name; final int qty; final double price;
  AppItemView(this.name, this.qty, this.price);
}



class AppOrder {
  String id, platform, branchId, customerName, phone, address, payment, status;
  List<AppItemView> items; double subtotal, deliveryFee, total;
  int createdAt; String? posInvoiceId, rejectReason;
  AppOrder.fromJson(Map j)
      : id = j['id'], platform = j['platform'], branchId = j['branchId'] ?? '',
        customerName = j['customerName'] ?? '', phone = j['phone'] ?? '', address = j['address'] ?? '',
        payment = j['payment'] ?? 'online', status = j['status'] ?? 'new',
        items = ((j['items'] as List?) ?? []).map((e) => AppItemView(e['name'], e['qty'], (e['price'] as num).toDouble())).toList(),
        subtotal = (j['subtotal'] as num?)?.toDouble() ?? 0,
        deliveryFee = (j['deliveryFee'] as num?)?.toDouble() ?? 0,
        total = (j['total'] as num?)?.toDouble() ?? 0,
        createdAt = j['createdAt'] ?? 0,
        posInvoiceId = j['posInvoiceId'], rejectReason = j['rejectReason'];



  Map<String, dynamic> toJson() => {'id': id, 'platform': platform, 'branchId': branchId, 'customerName': customerName,
      'phone': phone, 'address': address, 'payment': payment, 'status': status,
      'items': items.map((e) => {'name': e.name, 'qty': e.qty, 'price': e.price}).toList(),
      'subtotal': subtotal, 'deliveryFee': deliveryFee, 'total': total, 'createdAt': createdAt,
      'posInvoiceId': posInvoiceId, 'rejectReason': rejectReason};
}
