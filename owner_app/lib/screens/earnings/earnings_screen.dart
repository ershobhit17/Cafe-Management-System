import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/earnings_service.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEarnings();
    });
  }

  void _loadEarnings() {
    final auth = context.read<AuthService>();
    context.read<EarningsService>().fetchEarnings(auth.currentCafeId, isDemo: auth.isDemoMode);
  }

  Future<void> _selectCustomRange() async {
    final auth = context.read<AuthService>();
    final earnings = context.read<EarningsService>();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: earnings.customRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: const Color(0xFFFF7A00)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      earnings.setCustomRange(picked, auth.currentCafeId, isDemo: auth.isDemoMode);
    }
  }

  void _confirmResetTodayShift() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restart_alt, color: Color(0xFFFF7A00)),
            SizedBox(width: 8),
            Text('Restart Today\'s Shift?'),
          ],
        ),
        content: const Text(
          'This will restart today\'s sales counter back to ₹0 from this moment onward (e.g. for closing register or opening a new shift).\n\nYour past orders are safely preserved in database analytics.',
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
            onPressed: () {
              Navigator.pop(ctx);
              final auth = context.read<AuthService>();
              context.read<EarningsService>().resetTodayShift(auth.currentCafeId, isDemo: auth.isDemoMode);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Today\'s register counter has been restarted to ₹0.')),
              );
            },
            child: const Text('Restart Counter to ₹0'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final earnings = context.watch<EarningsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings & Revenue', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Revenue',
            onPressed: _loadEarnings,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadEarnings(),
        color: const Color(0xFFFF7A00),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Error banner if cloud sync failed
              if (earnings.errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          earnings.errorMessage!,
                          style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadEarnings,
                        child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

              // Active Shift Reset Banner (if enabled)
              if (earnings.hasActiveShiftReset)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFCC80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_toggle_off, color: Color(0xFFFF7A00), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Shift active since ${DateFormat('hh:mm a').format(earnings.shiftResetTime!)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE65100)),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        onPressed: () {
                          earnings.restoreFullDayView(auth.currentCafeId, isDemo: auth.isDemoMode);
                        },
                        child: const Text('Show Full Day', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),

              // 1. DEDICATED SALES OVERVIEW CARDS (Today, Week, Month)
              const Text('Sales Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildPeriodCard(
                      title: 'TODAY',
                      amount: earnings.todayRevenue,
                      orders: earnings.todayOrders,
                      icon: Icons.today,
                      color: const Color(0xFFFF7A00),
                      isActive: earnings.selectedRange == EarningsRange.today,
                      onTap: () => earnings.setRange(EarningsRange.today, auth.currentCafeId, isDemo: auth.isDemoMode),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPeriodCard(
                      title: 'THIS WEEK',
                      amount: earnings.weeklyRevenue,
                      orders: earnings.weeklyOrders,
                      icon: Icons.calendar_view_week,
                      color: Colors.blue.shade700,
                      isActive: earnings.selectedRange == EarningsRange.thisWeek,
                      onTap: () => earnings.setRange(EarningsRange.thisWeek, auth.currentCafeId, isDemo: auth.isDemoMode),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildPeriodCard(
                      title: 'THIS MONTH',
                      amount: earnings.monthlyRevenue,
                      orders: earnings.monthlyOrders,
                      icon: Icons.calendar_month,
                      color: Colors.teal.shade700,
                      isActive: earnings.selectedRange == EarningsRange.thisMonth,
                      onTap: () => earnings.setRange(EarningsRange.thisMonth, auth.currentCafeId, isDemo: auth.isDemoMode),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. HERO REVENUE CARD FOR SELECTED FILTER
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF7A00), Color(0xFFFF9E43)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _getRangeTitle(earnings.selectedRange),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${earnings.totalOrders} Orders',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${earnings.totalRevenue.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Paid vs Pending Split
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, size: 12, color: Color(0xFF81C784)),
                                const SizedBox(width: 4),
                                Text(
                                  'Paid: ₹${earnings.paidRevenue.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (earnings.pendingRevenue > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time, size: 12, color: Color(0xFFFFD54F)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Serving: ₹${earnings.pendingRevenue.toStringAsFixed(0)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Action buttons below Hero Card
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt, size: 18, color: Color(0xFFFF7A00)),
                      label: const Text('Restart Shift (₹0)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF7A00),
                        side: const BorderSide(color: Color(0xFFFF7A00)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _confirmResetTodayShift,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        earnings.selectedRange == EarningsRange.custom && earnings.customRange != null
                            ? '${DateFormat('d MMM').format(earnings.customRange!.start)} - ${DateFormat('d MMM').format(earnings.customRange!.end)}'
                            : 'Custom Date',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _selectCustomRange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Secondary Metrics (Total Orders & AOV)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Fulfilled Orders',
                      '${earnings.totalOrders}',
                      Icons.receipt_long,
                      Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      'Avg Order Value',
                      '₹${earnings.averageOrderValue.toStringAsFixed(0)}',
                      Icons.trending_up,
                      Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 3. REVENUE TREND BAR CHART
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Revenue Trend',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Daily Breakdown',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 220,
                        child: earnings.chartPoints.isEmpty || earnings.chartPoints.every((p) => p.amount == 0)
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No sales recorded in this period',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'New customer orders will appear here automatically',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                    ),
                                  ],
                                ),
                              )
                            : BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  maxY: (earnings.chartPoints.map((p) => p.amount).fold<double>(0, (a, b) => a > b ? a : b) * 1.25)
                                      .clamp(500, 100000),
                                  barTouchData: BarTouchData(
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                        final pt = earnings.chartPoints[group.x];
                                        return BarTooltipItem(
                                          '${DateFormat('d MMM').format(pt.date)}\n₹${pt.amount.toStringAsFixed(0)} (${pt.orderCount} orders)',
                                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                        );
                                      },
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    show: true,
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (val, meta) {
                                          final idx = val.toInt();
                                          if (idx < 0 || idx >= earnings.chartPoints.length) {
                                            return const SizedBox.shrink();
                                          }
                                          if (earnings.chartPoints.length > 7 && idx % 3 != 0) {
                                            return const SizedBox.shrink();
                                          }
                                          final pt = earnings.chartPoints[idx];
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Text(
                                              DateFormat('d/M').format(pt.date),
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 42,
                                        getTitlesWidget: (val, meta) {
                                          if (val == 0) return const SizedBox.shrink();
                                          if (val >= 1000) {
                                            return Text(
                                              '₹${(val / 1000).toStringAsFixed(0)}k',
                                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                            );
                                          }
                                          return Text(
                                            '₹${val.toStringAsFixed(0)}',
                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                          );
                                        },
                                      ),
                                    ),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  ),
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    getDrawingHorizontalLine: (value) => FlLine(
                                      color: Colors.grey.withValues(alpha: 0.15),
                                      strokeWidth: 1,
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  barGroups: earnings.getBarGroups(),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRangeTitle(EarningsRange range) {
    switch (range) {
      case EarningsRange.today:
        return "TODAY'S REVENUE";
      case EarningsRange.thisWeek:
        return "THIS WEEK'S REVENUE";
      case EarningsRange.thisMonth:
        return "THIS MONTH'S REVENUE";
      case EarningsRange.custom:
        return "CUSTOM PERIOD REVENUE";
    }
  }

  Widget _buildPeriodCard({
    required String title,
    required double amount,
    required int orders,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color : Colors.grey.shade300,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: isActive ? color : Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isActive ? color : Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '₹${amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isActive ? color : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$orders orders',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color iconColor) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
