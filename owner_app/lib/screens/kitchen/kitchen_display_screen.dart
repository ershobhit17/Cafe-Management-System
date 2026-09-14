import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/order_model.dart';
import '../../services/auth_service.dart';
import '../../services/kot_print_service.dart';
import '../../services/order_service.dart';
import '../../services/sound_service.dart';

class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen> {
  Timer? _tickerTimer;
  String _filterStage = 'ACTIVE'; // 'ACTIVE', 'PLACED', 'PREPARING', 'READY'

  @override
  void initState() {
    super.initState();
    // Refresh elapsed time counters every 30 seconds
    _tickerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadKitchenOrders();
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  void _loadKitchenOrders() {
    final auth = context.read<AuthService>();
    final orderService = context.read<OrderService>();
    orderService.fetchOrders(auth.currentCafeId, isDemo: auth.isDemoMode);
    orderService.subscribeToRealtimeOrders(auth.currentCafeId, isDemo: auth.isDemoMode);
  }

  String _getElapsedTimeString(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
  }

  Color _getUrgencyColor(DateTime createdAt) {
    final mins = DateTime.now().difference(createdAt).inMinutes;
    if (mins >= 20) return Colors.red.shade700;
    if (mins >= 10) return Colors.amber.shade800;
    return Colors.green.shade700;
  }

  Future<void> _updateStatus(OrderModel order, String newStatus) async {
    final auth = context.read<AuthService>();
    final orderService = context.read<OrderService>();

    final ok = await orderService.updateOrderStatus(
      order.id,
      newStatus,
      isDemo: auth.isDemoMode,
      cafeId: auth.currentCafeId,
    );

    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Order #${order.shortId} moved to ${newStatus.toUpperCase()}'),
        ),
      );
    }
  }

  void _confirmCancelOrder(OrderModel order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text('Cancel Order?'),
          ],
        ),
        content: Text('Are you sure you want to cancel order #${order.shortId} for Table #${order.tableNumber}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(order, 'cancelled');
            },
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
  }

  List<OrderModel> _filterOrders(List<OrderModel> allOrders) {
    final kitchenOrders = allOrders.where((o) {
      final s = o.status.toLowerCase();
      return s == 'placed' || s == 'pending' || s == 'preparing' || s == 'ready';
    }).toList();

    // Sort: oldest placed first (FIFO for kitchen)
    kitchenOrders.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (_filterStage == 'PLACED') {
      return kitchenOrders.where((o) => o.status.toLowerCase() == 'placed' || o.status.toLowerCase() == 'pending').toList();
    } else if (_filterStage == 'PREPARING') {
      return kitchenOrders.where((o) => o.status.toLowerCase() == 'preparing').toList();
    } else if (_filterStage == 'READY') {
      return kitchenOrders.where((o) => o.status.toLowerCase() == 'ready').toList();
    }

    return kitchenOrders;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final orderService = context.watch<OrderService>();
    final soundService = context.watch<SoundService>();
    final cafeName = auth.currentCafeName.isNotEmpty ? auth.currentCafeName : 'SnapServe Cafe';

    final filteredOrders = _filterOrders(orderService.orders);
    final totalActiveKitchen = orderService.orders.where((o) {
      final s = o.status.toLowerCase();
      return s == 'placed' || s == 'pending' || s == 'preparing' || s == 'ready';
    }).length;

    const primaryColor = Color(0xFFFF7A00);

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E24), // High-contrast dark kitchen station background
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        foregroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.soup_kitchen, size: 18, color: Colors.white),
                  SizedBox(width: 6),
                  Text('KDS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cafeName • Kitchen Display',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '$totalActiveKitchen Tickets Live',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              soundService.isSoundEnabled ? Icons.notifications_active : Icons.notifications_off,
              color: soundService.isSoundEnabled ? Colors.amber : Colors.grey,
            ),
            tooltip: 'Toggle Order Bell Chime',
            onPressed: () => soundService.toggleSound(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Tickets',
            onPressed: _loadKitchenOrders,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: const Color(0xFF16161A),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildFilterChip('ACTIVE', 'All Active ($totalActiveKitchen)'),
                const SizedBox(width: 8),
                _buildFilterChip('PLACED', 'New / Placed'),
                const SizedBox(width: 8),
                _buildFilterChip('PREPARING', 'Preparing'),
                const SizedBox(width: 8),
                _buildFilterChip('READY', 'Ready for Pickup'),
              ],
            ),
          ),
        ),
      ),
      body: orderService.isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : filteredOrders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 72, color: Colors.green.shade400),
                      const SizedBox(height: 16),
                      const Text(
                        'Kitchen Queue is Clear! 👨‍🍳✨',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Incoming table orders will automatically chime & appear here in real time.',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth > 1100
                        ? 3
                        : constraints.maxWidth > 650
                            ? 2
                            : 1;

                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: crossAxisCount == 1 ? 1.45 : 1.15,
                      ),
                      itemCount: filteredOrders.length,
                      itemBuilder: (context, index) {
                        final order = filteredOrders[index];
                        return _buildKitchenCard(order, cafeName);
                      },
                    );
                  },
                ),
    );
  }

  Widget _buildFilterChip(String stage, String label) {
    final isSelected = _filterStage == stage;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFFFF7A00),
      backgroundColor: const Color(0xFF2A2A32),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _filterStage = stage),
    );
  }

  Widget _buildKitchenCard(OrderModel order, String cafeName) {
    final normStatus = order.status.toLowerCase();
    final elapsedStr = _getElapsedTimeString(order.createdAt);
    final urgencyColor = _getUrgencyColor(order.createdAt);

    Color statusBadgeColor = Colors.amber.shade800;
    String statusTitle = 'PLACED';

    if (normStatus == 'preparing') {
      statusBadgeColor = const Color(0xFFFF7A00);
      statusTitle = 'PREPARING';
    } else if (normStatus == 'ready') {
      statusBadgeColor = Colors.blue.shade600;
      statusTitle = 'READY';
    }

    return Card(
      color: const Color(0xFF26262E),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: normStatus == 'placed' || normStatus == 'pending'
              ? const Color(0xFFFF7A00)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar: Table Badge, Order # & Elapsed Timer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7A00),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'TABLE #${order.tableNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '#${order.shortId}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                // Elapsed Ticker Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: urgencyColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: urgencyColor, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 14, color: urgencyColor),
                      const SizedBox(width: 4),
                      Text(
                        elapsedStr,
                        style: TextStyle(
                          color: urgencyColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Status Indicator Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusBadgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusTitle,
                    style: TextStyle(
                      color: statusBadgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  DateFormat('hh:mm a').format(order.createdAt),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),

            // Chef Special Instructions Banner if present
            if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade600, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.edit_note, color: Colors.amber, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Note: ${order.notes!.trim()}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(color: Colors.white12, height: 16),

            // Items List
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: order.items.length,
                itemBuilder: (context, idx) {
                  final item = order.items[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${item.quantity}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.menuItemName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            // Action Buttons: Lifecycle State & Print KOT
            Row(
              children: [
                // Print KOT Button
                OutlinedButton.icon(
                  onPressed: () => KotPrintService.printKot(order, cafeName: cafeName),
                  icon: const Icon(Icons.print, size: 16, color: Colors.white70),
                  label: const Text('KOT', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 6),

                // Cancel Button
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, size: 20, color: Colors.redAccent),
                  tooltip: 'Cancel Order',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmCancelOrder(order),
                ),
                const SizedBox(width: 6),

                // Primary Next-Step Action Button
                Expanded(
                  child: _buildLifecycleActionButton(order),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifecycleActionButton(OrderModel order) {
    final normStatus = order.status.toLowerCase();

    if (normStatus == 'placed' || normStatus == 'pending') {
      return ElevatedButton.icon(
        onPressed: () => _updateStatus(order, 'preparing'),
        icon: const Icon(Icons.soup_kitchen, size: 16),
        label: const Text('Start Preparing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF7A00),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else if (normStatus == 'preparing') {
      return ElevatedButton.icon(
        onPressed: () => _updateStatus(order, 'ready'),
        icon: const Icon(Icons.check_circle_outline, size: 16),
        label: const Text('Mark Ready', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else if (normStatus == 'ready') {
      return ElevatedButton.icon(
        onPressed: () => _updateStatus(order, 'served'),
        icon: const Icon(Icons.room_service, size: 16),
        label: const Text('Mark Served', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    return Container();
  }
}
