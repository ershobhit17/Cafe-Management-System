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
      lastDate: DateTime.now(),
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final earnings = context.watch<EarningsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings & Revenue', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadEarnings),
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
              // Date Range Segmented Control
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildRangeChip(EarningsRange.today, 'Today', earnings, auth),
                    const SizedBox(width: 8),
                    _buildRangeChip(EarningsRange.thisWeek, 'This Week', earnings, auth),
                    const SizedBox(width: 8),
                    _buildRangeChip(EarningsRange.thisMonth, 'This Month', earnings, auth),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.date_range, size: 16),
                          const SizedBox(width: 4),
                          Text(earnings.selectedRange == EarningsRange.custom && earnings.customRange != null
                              ? '${DateFormat('d MMM').format(earnings.customRange!.start)} - ${DateFormat('d MMM').format(earnings.customRange!.end)}'
                              : 'Custom'),
                        ],
                      ),
                      selected: earnings.selectedRange == EarningsRange.custom,
                      selectedColor: const Color(0xFFFF7A00),
                      labelStyle: TextStyle(
                        color: earnings.selectedRange == EarningsRange.custom ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => _selectCustomRange(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Hero Revenue Card
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [const Color(0xFFFF7A00), const Color(0xFFFF9E43)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        earnings.selectedRange == EarningsRange.today
                            ? "TODAY'S EARNINGS"
                            : 'TOTAL REVENUE',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
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
                      const SizedBox(height: 6),
                      Text(
                        'Auto-resets daily at 00:00 • Real-time verified',
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Secondary Metrics (Orders count & AOV)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Completed Orders',
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

              // Chart Section
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
                            'Day-wise breakdown',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 220,
                        child: earnings.chartPoints.isEmpty
                            ? const Center(child: Text('No revenue data for selected period'))
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
                                          // Show label occasionally if many days
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
                                        reservedSize: 38,
                                        getTitlesWidget: (val, meta) {
                                          if (val == 0) return const SizedBox.shrink();
                                          return Text(
                                            '₹${(val / 1000).toStringAsFixed(0)}k',
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
                                      color: Colors.grey.withOpacity(0.15),
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

  Widget _buildRangeChip(EarningsRange range, String label, EarningsService earnings, AuthService auth) {
    final isSelected = earnings.selectedRange == range;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFFFF7A00),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => earnings.setRange(range, auth.currentCafeId, isDemo: auth.isDemoMode),
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
