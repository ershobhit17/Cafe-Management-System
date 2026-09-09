import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

enum EarningsRange { today, thisWeek, thisMonth, custom }

class DailyEarningPoint {
  final DateTime date;
  final double amount;
  final int orderCount;

  DailyEarningPoint({required this.date, required this.amount, required this.orderCount});
}

class EarningsService extends ChangeNotifier {
  bool _isLoading = false;
  EarningsRange _selectedRange = EarningsRange.today;
  DateTimeRange? _customRange;

  double _totalRevenue = 0.0;
  int _totalOrders = 0;
  double _averageOrderValue = 0.0;
  List<DailyEarningPoint> _chartPoints = [];

  bool get isLoading => _isLoading;
  EarningsRange get selectedRange => _selectedRange;
  DateTimeRange? get customRange => _customRange;
  double get totalRevenue => _totalRevenue;
  int get totalOrders => _totalOrders;
  double get averageOrderValue => _averageOrderValue;
  List<DailyEarningPoint> get chartPoints => _chartPoints;

  void setRange(EarningsRange range, String cafeId, {bool isDemo = false}) {
    _selectedRange = range;
    fetchEarnings(cafeId, isDemo: isDemo);
  }

  void setCustomRange(DateTimeRange range, String cafeId, {bool isDemo = false}) {
    _selectedRange = EarningsRange.custom;
    _customRange = range;
    fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<void> fetchEarnings(String cafeId, {bool isDemo = false}) async {
    _isLoading = true;
    notifyListeners();

    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedRange) {
      case EarningsRange.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case EarningsRange.thisWeek:
        // Beginning of week (Monday)
        startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        break;
      case EarningsRange.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case EarningsRange.custom:
        startDate = _customRange != null ? _customRange!.start : DateTime(now.year, now.month, now.day);
        endDate = _customRange != null
            ? DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day, 23, 59, 59)
            : endDate;
        break;
    }

    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 250));
      _generateDemoEarnings(startDate, endDate);
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select('total_amount, created_at')
          .eq('cafe_id', cafeId)
          .eq('status', 'paid')
          .gte('created_at', startDate.toIso8601String())
          .lte('created_at', endDate.toIso8601String())
          .order('created_at');

      double sum = 0.0;
      final Map<String, List<double>> dayMap = {};

      for (var row in (res as List)) {
        final amt = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
        final date = DateTime.tryParse(row['created_at'] as String) ?? DateTime.now();
        final key = DateFormat('yyyy-MM-dd').format(date);

        sum += amt;
        dayMap.putIfAbsent(key, () => []).add(amt);
      }

      _totalRevenue = sum;
      _totalOrders = (res as List).length;
      _averageOrderValue = _totalOrders > 0 ? _totalRevenue / _totalOrders : 0.0;

      // Build daily points
      _chartPoints = [];
      final daysCount = endDate.difference(startDate).inDays + 1;
      for (int i = 0; i < (daysCount > 31 ? 31 : daysCount); i++) {
        final d = startDate.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        final amounts = dayMap[key] ?? [];
        final daySum = amounts.fold(0.0, (acc, val) => acc + val);
        _chartPoints.add(DailyEarningPoint(date: d, amount: daySum, orderCount: amounts.length));
      }
    } catch (e) {
      debugPrint('Error fetching earnings: $e');
      _generateDemoEarnings(startDate, endDate);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _generateDemoEarnings(DateTime start, DateTime end) {
    _chartPoints = [];
    final daysCount = end.difference(start).inDays + 1;
    double sum = 0.0;
    int orders = 0;

    for (int i = 0; i < (daysCount > 14 ? 14 : daysCount); i++) {
      final d = start.add(Duration(days: i));
      // Deterministic demo revenue based on day
      final dayRevenue = ((i * 370 + 820) % 2400) + 450.0;
      final dayOrders = (dayRevenue / 340).round() + 1;
      sum += dayRevenue;
      orders += dayOrders;
      _chartPoints.add(DailyEarningPoint(date: d, amount: dayRevenue, orderCount: dayOrders));
    }

    if (_selectedRange == EarningsRange.today) {
      _totalRevenue = 3450.0;
      _totalOrders = 11;
      _averageOrderValue = 313.6;
    } else {
      _totalRevenue = sum;
      _totalOrders = orders;
      _averageOrderValue = orders > 0 ? sum / orders : 0.0;
    }
  }

  List<BarChartGroupData> getBarGroups() {
    return _chartPoints.asMap().entries.map((entry) {
      final idx = entry.key;
      final point = entry.value;
      return BarChartGroupData(
        x: idx,
        barRods: [
          BarChartRodData(
            toY: point.amount,
            color: const Color(0xFFFF7A00),
            width: 14,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();
  }
}
