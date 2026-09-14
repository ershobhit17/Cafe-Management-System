import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/order_model.dart';
import 'sound_service.dart';

class OrderService extends ChangeNotifier {
  List<OrderModel> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  RealtimeChannel? _realtimeChannel;
  Timer? _pollingTimer;
  bool _hasNewOrderAlert = false;
  bool _hasInitialFetchDone = false;

  List<OrderModel> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasNewOrderAlert => _hasNewOrderAlert;

  void clearNewOrderAlert() {
    _hasNewOrderAlert = false;
    notifyListeners();
  }

  // Active / Kitchen Orders (pending, preparing, served)
  List<OrderModel> get liveOrders =>
      _orders.where((o) => o.status != 'paid').toList();

  // Completed Orders (paid)
  List<OrderModel> get completedOrders =>
      _orders.where((o) => o.status == 'paid').toList();

  // Demo Fallback Orders
  final List<OrderModel> _demoOrders = [
    OrderModel(
      id: 'ord-101',
      cafeId: SupabaseConfig.demoCafeId,
      tableId: 't-3',
      tableNumber: 3,
      status: 'pending',
      totalAmount: 479,
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      items: [
        OrderItemModel(id: 'oi-1', orderId: 'ord-101', menuItemId: 'd-1', menuItemName: 'Caramel Macchiato', quantity: 1, priceAtOrderTime: 199),
        OrderItemModel(id: 'oi-2', orderId: 'ord-101', menuItemId: 'd-5', menuItemName: 'Pesto Grilled Sourdough', quantity: 1, priceAtOrderTime: 280),
      ],
    ),
    OrderModel(
      id: 'ord-102',
      cafeId: SupabaseConfig.demoCafeId,
      tableId: 't-1',
      tableNumber: 1,
      status: 'preparing',
      totalAmount: 648,
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
      items: [
        OrderItemModel(id: 'oi-3', orderId: 'ord-102', menuItemId: 'd-3', menuItemName: 'Sweet Cream Cold Brew', quantity: 1, priceAtOrderTime: 249),
        OrderItemModel(id: 'oi-4', orderId: 'ord-102', menuItemId: 'd-8', menuItemName: 'Artisan Margherita Pizza', quantity: 1, priceAtOrderTime: 399),
      ],
    ),
    OrderModel(
      id: 'ord-103',
      cafeId: SupabaseConfig.demoCafeId,
      tableId: 't-5',
      tableNumber: 5,
      status: 'served',
      totalAmount: 239,
      createdAt: DateTime.now().subtract(const Duration(minutes: 24)),
      items: [
        OrderItemModel(id: 'oi-5', orderId: 'ord-103', menuItemId: 'd-9', menuItemName: 'New York Cheesecake', quantity: 1, priceAtOrderTime: 239),
      ],
    ),
  ];

  Future<void> fetchOrders(String cafeId, {bool isDemo = false}) async {
    // If Supabase is NOT configured, use static fallback
    if (!SupabaseConfig.isConfigured) {
      _isLoading = true;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 300));
      _orders = List.from(_demoOrders);
      _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select('*, tables(table_number), order_items(*, menu_items(name))')
          .eq('cafe_id', cafeId)
          .order('created_at', ascending: false);

      final List<OrderModel> loaded = [];
      for (var row in (res as List)) {
        final mapRow = Map<String, dynamic>.from(row as Map);
        final rawItems = mapRow['order_items'] as List? ?? [];
        final items = rawItems.map((itemJson) {
          final mapItem = Map<String, dynamic>.from(itemJson as Map);
          return OrderItemModel.fromJson(mapItem);
        }).toList();
        loaded.add(OrderModel.fromJson(mapRow, items: items));
      }

      // Check if new orders arrived to trigger badge & sound effect
      if (_hasInitialFetchDone) {
        final existingIds = _orders.map((o) => o.id).toSet();
        final hasBrandNewOrder = loaded.any((o) => !existingIds.contains(o.id));
        if (hasBrandNewOrder) {
          _hasNewOrderAlert = true;
          SoundService.instance.playOrderAlert();
        }
      } else {
        _hasInitialFetchDone = true;
      }

      _orders = loaded;
      _errorMessage = null;
    } catch (e) {
      debugPrint('fetchOrders error: $e');
      if (_orders.isEmpty) {
        _orders = List.from(_demoOrders);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void subscribeToRealtimeOrders(String cafeId, {bool isDemo = false}) {
    if (!SupabaseConfig.isConfigured) return;

    // Dispose previous channel if active
    _realtimeChannel?.unsubscribe();

    _realtimeChannel = Supabase.instance.client
        .channel('owner_orders_channel_$cafeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'cafe_id',
            value: cafeId,
          ),
          callback: (payload) async {
            debugPrint('Realtime order change event: ${payload.eventType}');
            if (payload.eventType == PostgresChangeEvent.insert) {
              _hasNewOrderAlert = true;
              SoundService.instance.playOrderAlert();
            }
            // Refresh orders list on any database modification
            await fetchOrders(cafeId, isDemo: isDemo);
          },
        )
        .subscribe();

    // Start 4-second polling fallback so orders are NEVER missed even if websocket sleeps
    startPeriodicRefresh(cafeId, isDemo: isDemo);
  }

  void startPeriodicRefresh(String cafeId, {bool isDemo = false}) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      fetchOrders(cafeId, isDemo: isDemo);
    });
  }

  Future<bool> updateOrderStatus(String orderId, String newStatus, {bool isDemo = false, required String cafeId}) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      _orders[index] = _orders[index].copyWith(status: newStatus);
      notifyListeners();
    }

    if (!SupabaseConfig.isConfigured) {
      return true;
    }

    try {
      await Supabase.instance.client
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update order status: $e';
      // Revert if error
      await fetchOrders(cafeId, isDemo: isDemo);
      return false;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<Map<String, dynamic>> closeDayAndCollect(String cafeId, {bool isDemo = false}) async {
    _isLoading = true;
    notifyListeners();

    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 300));
      final eligible = _orders.where((o) => o.status.toLowerCase() == 'served').toList();
      double collected = 0;
      for (var o in eligible) {
        collected += o.totalAmount;
        final idx = _orders.indexWhere((item) => item.id == o.id);
        if (idx != -1) {
          _orders[idx] = _orders[idx].copyWith(status: 'paid');
        }
      }
      _isLoading = false;
      notifyListeners();
      return {
        'success': true,
        'orders_count': eligible.length,
        'collected_amount': collected,
      };
    }

    try {
      final res = await Supabase.instance.client.rpc('close_day_and_collect', params: {
        'p_cafe_id': cafeId,
      });

      await fetchOrders(cafeId, isDemo: isDemo);

      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'success': true, 'orders_count': 0, 'collected_amount': 0.0};
    } catch (e) {
      debugPrint('close_day_and_collect RPC error: $e, falling back to status update');
      try {
        final eligible = _orders.where((o) => o.status.toLowerCase() == 'served').toList();
        double collected = 0;
        for (var o in eligible) {
          collected += o.totalAmount;
          await Supabase.instance.client
              .from('orders')
              .update({'status': 'paid'})
              .eq('id', o.id);
        }
        await fetchOrders(cafeId, isDemo: isDemo);
        return {
          'success': true,
          'orders_count': eligible.length,
          'collected_amount': collected,
        };
      } catch (err2) {
        _errorMessage = 'Failed to collect orders: $err2';
        return {'success': false, 'error': err2.toString()};
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

}
