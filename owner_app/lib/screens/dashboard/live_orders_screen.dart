import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/order_model.dart';
import '../../services/auth_service.dart';
import '../../services/earnings_service.dart';
import '../../services/kot_print_service.dart';
import '../../services/order_service.dart';
import '../../services/sound_service.dart';
import '../kitchen/kitchen_display_screen.dart';

class LiveOrdersScreen extends StatefulWidget {
  const LiveOrdersScreen({super.key});

  @override
  State<LiveOrdersScreen> createState() => _LiveOrdersScreenState();
}

class _LiveOrdersScreenState extends State<LiveOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['All Active', 'Pending', 'Preparing', 'Ready', 'Served', 'Paid History'];

  String? _lastCafeId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrders();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    if (auth.currentCafeId != _lastCafeId) {
      _lastCafeId = auth.currentCafeId;
      _loadOrders();
    }
  }

  void _loadOrders() {
    final auth = context.read<AuthService>();
    final orderService = context.read<OrderService>();
    orderService.fetchOrders(auth.currentCafeId, isDemo: auth.isDemoMode);
    orderService.subscribeToRealtimeOrders(auth.currentCafeId, isDemo: auth.isDemoMode);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'placed':
      case 'pending':
        return Colors.amber.shade800;
      case 'preparing':
        return const Color(0xFFFF7A00);
      case 'ready':
        return Colors.blue.shade700;
      case 'served':
        return Colors.teal.shade700;
      case 'paid':
        return Colors.green.shade600;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  Future<void> _updateOrderStatusAndEarnings(
    OrderModel order,
    String newStatus,
    AuthService auth,
    OrderService orderService,
  ) async {
    final ok = await orderService.updateOrderStatus(
      order.id,
      newStatus,
      isDemo: auth.isDemoMode,
      cafeId: auth.currentCafeId,
    );
    if (ok && mounted) {
      context.read<EarningsService>().fetchEarnings(auth.currentCafeId, isDemo: auth.isDemoMode);
      if (newStatus == 'paid') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            content: Text('Order #${order.shortId} marked Paid! ₹${order.totalAmount.toStringAsFixed(0)} added to Earnings.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildStatusActionBtn(OrderModel order, AuthService auth, OrderService orderService) {
    String nextLabel = '';
    String nextStatus = '';
    Color btnColor = const Color(0xFFFF7A00);
    IconData icon = Icons.check;

    final normStatus = order.status.toLowerCase();
    final cafeName = auth.currentCafeName.isNotEmpty ? auth.currentCafeName : 'SnapServe Cafe';

    switch (normStatus) {
      case 'placed':
      case 'pending':
        nextLabel = 'Start Preparing';
        nextStatus = 'preparing';
        btnColor = const Color(0xFFFF7A00);
        icon = Icons.soup_kitchen;
        break;
      case 'preparing':
        nextLabel = 'Mark Ready';
        nextStatus = 'ready';
        btnColor = Colors.blue.shade700;
        icon = Icons.check_circle_outline;
        break;
      case 'ready':
        nextLabel = 'Mark Served';
        nextStatus = 'served';
        btnColor = Colors.teal.shade700;
        icon = Icons.room_service;
        break;
      case 'served':
        nextLabel = 'Mark Paid (₹${order.totalAmount.toStringAsFixed(0)})';
        nextStatus = 'paid';
        btnColor = Colors.green.shade700;
        icon = Icons.payments_outlined;
        break;
      case 'paid':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.print, size: 18),
              tooltip: 'Print KOT / Receipt',
              visualDensity: VisualDensity.compact,
              onPressed: () => KotPrintService.printKot(order, cafeName: cafeName),
            ),
            const Chip(
              avatar: Icon(Icons.check_circle, size: 16, color: Colors.green),
              label: Text('Paid & Closed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
              backgroundColor: Color(0xFFE8F5E9),
            ),
          ],
        );
      case 'cancelled':
        return const Chip(
          avatar: Icon(Icons.cancel, size: 16, color: Colors.red),
          label: Text('Cancelled', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
          backgroundColor: Color(0xFFFFEBEE),
        );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 1-Click Print KOT Thermal Receipt Button
        OutlinedButton.icon(
          onPressed: () => KotPrintService.printKot(order, cafeName: cafeName),
          icon: const Icon(Icons.print, size: 14, color: Color(0xFFFF7A00)),
          label: const Text('Print KOT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF7A00))),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFF7A00)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),

        // Quick Direct Paid button if customer pays before order is served
        if (normStatus == 'placed' || normStatus == 'pending' || normStatus == 'preparing' || normStatus == 'ready')
          OutlinedButton.icon(
            onPressed: () => _updateOrderStatusAndEarnings(order, 'paid', auth, orderService),
            icon: const Icon(Icons.payments_outlined, size: 14, color: Colors.green),
            label: Text(
              'Collect ₹${order.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.green),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),

        // Primary Next-Step Action Button
        ElevatedButton.icon(
          onPressed: () => _updateOrderStatusAndEarnings(order, nextStatus, auth, orderService),
          icon: Icon(icon, size: 16),
          label: Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: btnColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  
  void _confirmCloseDayAndCollect(BuildContext context, AuthService auth, OrderService orderService) {
    final eligibleOrders = orderService.orders.where((o) => o.status.toLowerCase() == 'served').toList();
    final double totalAmount = eligibleOrders.fold(0.0, (sum, o) => sum + o.totalAmount);

    if (eligibleOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible served orders to collect. Only completed/served orders can be settled.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.point_of_sale, color: Color(0xFFFF7A00)),
            SizedBox(width: 8),
            Text('Close Day & Collect?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You are about to mark all eligible completed orders as paid and record today\'s collected amount.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Orders', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        '${eligibleOrders.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                      ),
                    ],
                  ),
                  Container(height: 30, width: 1, color: Colors.grey.shade400),
                  Column(
                    children: [
                      const Text('Collected', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        '₹${totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFFF7A00)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Note: Pending and Preparing orders will remain active in the kitchen.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7A00),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await orderService.closeDayAndCollect(auth.currentCafeId, isDemo: auth.isDemoMode);
              if (context.mounted) {
                context.read<EarningsService>().fetchEarnings(auth.currentCafeId, isDemo: auth.isDemoMode);
                final collected = res['collected_amount'] ?? totalAmount;
                final count = res['orders_count'] ?? eligibleOrders.length;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade800,
                    content: Text('₹${collected is num ? collected.toStringAsFixed(0) : collected} collected successfully ($count orders settled).'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('Confirm Collection'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final orderService = context.watch<OrderService>();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10.0, top: 9.0, bottom: 9.0, right: 6.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF7A00).withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/app_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.restaurant, color: Color(0xFFFF7A00)),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              auth.currentCafeName.isNotEmpty ? auth.currentCafeName : 'SnapServe Cafe',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Live Orders', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${orderService.liveOrders.length} Active',
                    style: const TextStyle(color: Color(0xFFFF7A00), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Consumer<SoundService>(
            builder: (ctx, sound, _) => IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              icon: Icon(
                sound.isSoundEnabled ? Icons.notifications_active : Icons.notifications_off,
                color: sound.isSoundEnabled ? const Color(0xFFFF7A00) : Colors.grey,
                size: 22,
              ),
              tooltip: sound.isSoundEnabled ? 'Sound alert active (tap to test bell)' : 'Sound muted (tap to enable)',
              onPressed: () async {
                if (sound.isSoundEnabled) {
                  await sound.testSound();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('🔔 Tested order alert bell.'), duration: Duration(seconds: 1)),
                    );
                  }
                } else {
                  await sound.setSoundEnabled(true);
                  await sound.testSound();
                }
              },
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            icon: const Icon(Icons.soup_kitchen, color: Color(0xFFFF7A00), size: 22),
            tooltip: 'Kitchen Display System (KDS)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const KitchenDisplayScreen()),
              );
            },
          ),
          if (!isMobile) ...[
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF7A00),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.point_of_sale, size: 16),
              label: const Text('Close Day & Collect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              onPressed: () => _confirmCloseDayAndCollect(context, auth, orderService),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Orders',
              onPressed: _loadOrders,
            ),
          ] else ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: 'Refresh Orders',
              onPressed: _loadOrders,
            ),
            PopupMenuButton<String>(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              icon: const Icon(Icons.more_vert, size: 22),
              tooltip: 'More Actions',
              onSelected: (action) {
                if (action == 'close_day') {
                  _confirmCloseDayAndCollect(context, auth, orderService);
                } else if (action == 'refresh') {
                  _loadOrders();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'close_day',
                  child: Row(
                    children: [
                      Icon(Icons.point_of_sale, color: Color(0xFFFF7A00), size: 20),
                      SizedBox(width: 10),
                      Text('Close Day & Collect', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 20),
                      SizedBox(width: 10),
                      Text('Refresh Orders'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: const Color(0xFFFF7A00),
          indicatorColor: const Color(0xFFFF7A00),
          tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
        ),
      ),
      body: Column(
        children: [
          // New Order Alert Banner
          if (orderService.hasNewOrderAlert)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFFF7A00),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '🔔 New order placed! Kitchen ticket created.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => orderService.clearNewOrderAlert(),
                  ),
                ],
              ),
            ),

          // Tab views
          Expanded(
            child: orderService.isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7A00)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOrdersList(orderService.liveOrders, auth, orderService),
                      _buildOrdersList(orderService.orders.where((o) => o.status.toLowerCase() == 'pending' || o.status.toLowerCase() == 'placed').toList(), auth, orderService),
                      _buildOrdersList(orderService.orders.where((o) => o.status.toLowerCase() == 'preparing').toList(), auth, orderService),
                      _buildOrdersList(orderService.orders.where((o) => o.status.toLowerCase() == 'ready').toList(), auth, orderService),
                      _buildOrdersList(orderService.orders.where((o) => o.status.toLowerCase() == 'served').toList(), auth, orderService),
                      _buildOrdersList(orderService.completedOrders, auth, orderService),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<OrderModel> orders, AuthService auth, OrderService orderService) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.restaurant_menu_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No orders in this stage',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFF7A00),
      onRefresh: () async => _loadOrders(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          final timeStr = DateFormat('hh:mm a').format(order.createdAt);
          final statusColor = _getStatusColor(order.status);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: order.status == 'pending' ? const Color(0xFFFF7A00).withValues(alpha: 0.5) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Table # and Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF7A00).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Table #${order.tableNumber}',
                              style: const TextStyle(
                                color: Color(0xFFFF7A00),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '#${order.shortId}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          order.status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Order Items
                  ...order.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${item.quantity}x',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.menuItemName,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                            ),
                          ),
                          Text(
                            '₹${item.subtotal.toStringAsFixed(0)}',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Special Cooking Instructions Note
                  if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit_note, size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Special Instructions: ${order.notes!.trim()}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(height: 20),

                  // Bottom Section: Time, Total & Responsive Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Placed: $timeStr', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      Text(
                        'Total: ₹${order.totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFFF7A00)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildStatusActionBtn(order, auth, orderService),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
