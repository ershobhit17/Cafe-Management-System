import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const _storage = FlutterSecureStorage();
  static const _kShiftResetKey = 'cafe_shift_reset_timestamp';

  bool _isLoading = false;
  EarningsRange _selectedRange = EarningsRange.today;
  DateTimeRange? _customRange;
  String? _errorMessage;

  // Selected range metrics
  double _totalRevenue = 0.0;
  double _paidRevenue = 0.0;
  double _pendingRevenue = 0.0;
  int _totalOrders = 0;
  double _averageOrderValue = 0.0;
  List<DailyEarningPoint> _chartPoints = [];

  // Dedicated period metrics (always computed for instant overview)
  double _todayRevenue = 0.0;
  int _todayOrders = 0;
  double _weeklyRevenue = 0.0;
  int _weeklyOrders = 0;
  double _monthlyRevenue = 0.0;
  int _monthlyOrders = 0;

  DateTime? _shiftResetTime;

  bool get isLoading => _isLoading;
  EarningsRange get selectedRange => _selectedRange;
  DateTimeRange? get customRange => _customRange;
  String? get errorMessage => _errorMessage;

  double get totalRevenue => _totalRevenue;
  double get paidRevenue => _paidRevenue;
  double get pendingRevenue => _pendingRevenue;
  int get totalOrders => _totalOrders;
  double get averageOrderValue => _averageOrderValue;
  List<DailyEarningPoint> get chartPoints => _chartPoints;

  double get todayRevenue => _todayRevenue;
  int get todayOrders => _todayOrders;
  double get weeklyRevenue => _weeklyRevenue;
  int get weeklyOrders => _weeklyOrders;
  double get monthlyRevenue => _monthlyRevenue;
  int get monthlyOrders => _monthlyOrders;

  DateTime? get shiftResetTime => _shiftResetTime;
  bool get hasActiveShiftReset => _shiftResetTime != null;

  EarningsService() {
    _initShiftReset();
  }

  Future<void> _initShiftReset() async {
    try {
      final saved = await _storage.read(key: _kShiftResetKey);
      if (saved != null) {
        final parsed = DateTime.tryParse(saved);
        if (parsed != null) {
          final now = DateTime.now();
          // Only apply if reset happened today (same calendar day)
          if (parsed.year == now.year && parsed.month == now.month && parsed.day == now.day) {
            _shiftResetTime = parsed;
          } else {
            await _storage.delete(key: _kShiftResetKey);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> resetTodayShift(String cafeId, {bool isDemo = false}) async {
    final now = DateTime.now();
    _shiftResetTime = now;
    try {
      await _storage.write(key: _kShiftResetKey, value: now.toIso8601String());
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<void> restoreFullDayView(String cafeId, {bool isDemo = false}) async {
    _shiftResetTime = null;
    try {
      await _storage.delete(key: _kShiftResetKey);
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

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
    _errorMessage = null;
    notifyListeners();

    final now = DateTime.now();
    DateTime rangeStart;
    DateTime rangeEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedRange) {
      case EarningsRange.today:
        rangeStart = _shiftResetTime ?? DateTime(now.year, now.month, now.day);
        break;
      case EarningsRange.thisWeek:
        // Beginning of current week (Monday)
        rangeStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        break;
      case EarningsRange.thisMonth:
        // 1st of current month
        rangeStart = DateTime(now.year, now.month, 1);
        break;
      case EarningsRange.custom:
        rangeStart = _customRange != null ? _customRange!.start : DateTime(now.year, now.month, now.day);
        rangeEnd = _customRange != null
            ? DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day, 23, 59, 59)
            : rangeEnd;
        break;
    }

    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 200));
      _generateDemoEarnings(rangeStart, rangeEnd);
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      // 1. Fetch Month-to-date orders to calculate Today, Week, Month and selected range accurately
      final monthStart = DateTime(now.year, now.month, 1);
      final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      final todayStart = _shiftResetTime ?? DateTime(now.year, now.month, now.day);

      // Query broad enough to cover month and custom range
      final queryStart = rangeStart.isBefore(monthStart) ? rangeStart : monthStart;
      final queryEnd = rangeEnd.isAfter(now) ? rangeEnd : now.add(const Duration(hours: 1));

      final res = await Supabase.instance.client
          .from('orders')
          .select('id, status, total_amount, created_at')
          .eq('cafe_id', cafeId)
          .gte('created_at', queryStart.toIso8601String())
          .lte('created_at', queryEnd.toIso8601String())
          .order('created_at', ascending: true);

      final List ordersList = res as List;

      // Temporary accumulators
      double todaySum = 0;
      int todayCount = 0;
      double weekSum = 0;
      int weekCount = 0;
      double monthSum = 0;
      int monthCount = 0;

      double selectedSum = 0;
      double selectedPaid = 0;
      double selectedPending = 0;
      int selectedCount = 0;
      final Map<String, List<double>> dayMap = {};

      for (var row in ordersList) {
        final amt = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
        final status = (row['status'] as String?)?.toLowerCase() ?? 'pending';
        final dt = DateTime.tryParse(row['created_at'] as String)?.toLocal() ?? DateTime.now();

        // Skip cancelled/rejected orders if any
        if (status == 'cancelled' || status == 'rejected') continue;

        // Month-to-date accumulation
        if (dt.isAfter(monthStart) || dt.isAtSameMomentAs(monthStart)) {
          monthSum += amt;
          monthCount++;
        }

        // Week-to-date accumulation
        if (dt.isAfter(weekStart) || dt.isAtSameMomentAs(weekStart)) {
          weekSum += amt;
          weekCount++;
        }

        // Today accumulation
        if (dt.isAfter(todayStart) || dt.isAtSameMomentAs(todayStart)) {
          todaySum += amt;
          todayCount++;
        }

        // Selected Range accumulation
        final inSelectedRange = (dt.isAfter(rangeStart) || dt.isAtSameMomentAs(rangeStart)) &&
            (dt.isBefore(rangeEnd) || dt.isAtSameMomentAs(rangeEnd));

        if (inSelectedRange) {
          selectedSum += amt;
          selectedCount++;
          if (status == 'paid') {
            selectedPaid += amt;
          } else {
            selectedPending += amt;
          }

          final dateKey = DateFormat('yyyy-MM-dd').format(dt);
          dayMap.putIfAbsent(dateKey, () => []).add(amt);
        }
      }

      // Assign period metrics
      _todayRevenue = todaySum;
      _todayOrders = todayCount;
      _weeklyRevenue = weekSum;
      _weeklyOrders = weekCount;
      _monthlyRevenue = monthSum;
      _monthlyOrders = monthCount;

      // Assign selected range metrics
      _totalRevenue = selectedSum;
      _paidRevenue = selectedPaid;
      _pendingRevenue = selectedPending;
      _totalOrders = selectedCount;
      _averageOrderValue = selectedCount > 0 ? selectedSum / selectedCount : 0.0;

      // Build daily chart points
      _chartPoints = [];
      final daysCount = rangeEnd.difference(rangeStart).inDays + 1;
      final displayLimit = daysCount > 31 ? 31 : daysCount;

      for (int i = 0; i < displayLimit; i++) {
        final d = rangeStart.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        final amounts = dayMap[key] ?? [];
        final daySum = amounts.fold(0.0, (acc, val) => acc + val);
        _chartPoints.add(DailyEarningPoint(date: d, amount: daySum, orderCount: amounts.length));
      }
    } catch (e) {
      debugPrint('Error fetching earnings: $e');
      _errorMessage = 'Cloud sync error: $e';
      // Do not replace real data with fake numbers on error
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
      final dayRevenue = ((i * 370 + 820) % 2400) + 450.0;
      final dayOrders = (dayRevenue / 340).round() + 1;
      sum += dayRevenue;
      orders += dayOrders;
      _chartPoints.add(DailyEarningPoint(date: d, amount: dayRevenue, orderCount: dayOrders));
    }

    _todayRevenue = 3450.0;
    _todayOrders = 11;
    _weeklyRevenue = 18900.0;
    _weeklyOrders = 62;
    _monthlyRevenue = 74500.0;
    _monthlyOrders = 245;

    if (_selectedRange == EarningsRange.today) {
      _totalRevenue = _todayRevenue;
      _paidRevenue = 2890.0;
      _pendingRevenue = 560.0;
      _totalOrders = _todayOrders;
      _averageOrderValue = 313.6;
    } else {
      _totalRevenue = sum;
      _paidRevenue = sum * 0.85;
      _pendingRevenue = sum * 0.15;
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
