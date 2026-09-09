import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/order_model.dart';
import '../../services/auth_service.dart';
import '../../services/order_service.dart';

class LiveOrdersScreen extends StatefulWidget {
  const LiveOrdersScreen({super.key});

  @override
  State<LiveOrdersScreen> createState() => _LiveOrdersScreenState();
}

class _LiveOrdersScreenState extends State<LiveOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['All Active', 'Pending', 'Preparing', 'Served', 'Paid History'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrders();
    });
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
      case 'pending':
        return Colors.amber.shade800;
      case 'preparing':
        return const Color(0xFFFF7A00);
      case 'served':
        return Colors.blue.shade600;
      case 'paid':
        return Colors.green.shade600;
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatusActionBtn(OrderModel order, AuthService auth, OrderService orderService) {
    String nextLabel = '';
    String nextStatus = '';
    Color btnColor = const Color(0xFFFF7A00);
    IconData icon = Icons.check;

    switch (order.status.toLowerCase()) {
      case 'pending':
        nextLabel = 'Start Preparing';
        nextStatus = 'preparing';
        btnColor = const Color(0xFFFF7A00);
        icon = Icons.soup_kitchen;
        break;
      case 'preparing':
        nextLabel = 'Mark Served';
        nextStatus = 'served';
        btnColor = Colors.blue.shade700;
        icon = Icons.room_service;
        break;
      case 'served':
        nextLabel = 'Mark Paid (₹${order.totalAmount.toStringAsFixed(0)})';
        nextStatus = 'paid';
        btnColor = Colors.green.shade700;
        icon = Icons.payments_outlined;
        break;
      case 'paid':
        return const Chip(
          avatar: Icon(Icons.check_circle, size: 16, color: Colors.green),
          label: Text('Paid & Closed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
          backgroundColor: Color(0xFFE8F5E9),
        );
    }

    return ElevatedButton.icon(
      onPressed: () {
        orderService.updateOrderStatus(
          order.id,
          nextStatus,
          isDemo: auth.isDemoMode,
          cafeId: auth.currentCafeId,
        );
      },
      icon: Icon(icon, size: 16),
      label: Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final orderService = context.watch<OrderService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Live Kitchen Orders', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7A00).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${orderService.liveOrders.length} Active',
                style: const TextStyle(color: Color(0xFFFF7A00), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Orders',
            onPressed: _loadOrders,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
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
                      _buildOrdersList(orderService.orders.where((o) => o.status == 'pending').toList(), auth, orderService),
                      _buildOrdersList(orderService.orders.where((o) => o.status == 'preparing').toList(), auth, orderService),
                      _buildOrdersList(orderService.orders.where((o) => o.status == 'served').toList(), auth, orderService),
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

    return ListView.builder(
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
              color: order.status == 'pending' ? const Color(0xFFFF7A00).withOpacity(0.5) : Colors.transparent,
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
                            color: const Color(0xFFFF7A00).withOpacity(0.12),
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
                          style: TextStyle(fontFamily: 'monospace', color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
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
                            color: Colors.grey.withOpacity(0.15),
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

                const Divider(height: 20),

                // Bottom Row: Time, Total & Action
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Placed: $timeStr', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          'Total: ₹${order.totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    _buildStatusActionBtn(order, auth, orderService),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
