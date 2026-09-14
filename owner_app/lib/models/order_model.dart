class OrderItemModel {
  final String id;
  final String orderId;
  final String menuItemId;
  final String menuItemName;
  final int quantity;
  final double priceAtOrderTime;

  OrderItemModel({
    required this.id,
    required this.orderId,
    required this.menuItemId,
    required this.menuItemName,
    required this.quantity,
    required this.priceAtOrderTime,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    String itemName = 'Menu Item';
    if (json['menu_items'] != null && json['menu_items'] is Map) {
      itemName = json['menu_items']['name'] as String? ?? itemName;
    } else if (json['name'] != null) {
      itemName = json['name'] as String;
    }

    final rawPrice = json['price_at_order_time'];
    final double price = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '') ?? 0.0);

    final rawQty = json['quantity'];
    final int qty = rawQty is num
        ? rawQty.toInt()
        : (int.tryParse(rawQty?.toString() ?? '') ?? 1);

    return OrderItemModel(
      id: json['id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      menuItemId: json['menu_item_id'] as String? ?? '',
      menuItemName: itemName,
      quantity: qty,
      priceAtOrderTime: price,
    );
  }

  double get subtotal => priceAtOrderTime * quantity;
}

class OrderModel {
  final String id;
  final String cafeId;
  final String tableId;
  final int tableNumber;
  final String status; // 'placed' | 'pending' | 'preparing' | 'ready' | 'served' | 'paid' | 'cancelled'
  final double totalAmount;
  final DateTime createdAt;
  final String? notes;
  final List<OrderItemModel> items;

  OrderModel({
    required this.id,
    required this.cafeId,
    required this.tableId,
    required this.tableNumber,
    required this.status,
    required this.totalAmount,
    required this.createdAt,
    this.notes,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> json, {List<OrderItemModel>? items}) {
    int tableNum = 1;
    if (json['tables'] != null && json['tables'] is Map) {
      final rawNum = json['tables']['table_number'];
      tableNum = rawNum is num
          ? rawNum.toInt()
          : (int.tryParse(rawNum?.toString() ?? '') ?? 1);
    } else if (json['table_number'] != null) {
      final rawNum = json['table_number'];
      tableNum = rawNum is num
          ? rawNum.toInt()
          : (int.tryParse(rawNum?.toString() ?? '') ?? 1);
    }

    final rawTotal = json['total_amount'];
    final double total = rawTotal is num
        ? rawTotal.toDouble()
        : (double.tryParse(rawTotal?.toString() ?? '') ?? 0.0);

    return OrderModel(
      id: json['id'] as String? ?? '',
      cafeId: json['cafe_id'] as String? ?? '',
      tableId: json['table_id'] as String? ?? '',
      tableNumber: tableNum,
      status: json['status'] as String? ?? 'pending',
      totalAmount: total,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      items: items ?? [],
    );
  }

  OrderModel copyWith({
    String? status,
    double? totalAmount,
    String? notes,
    List<OrderItemModel>? items,
  }) {
    return OrderModel(
      id: id,
      cafeId: cafeId,
      tableId: tableId,
      tableNumber: tableNumber,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      items: items ?? this.items,
    );
  }

  String get shortId => id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
}
