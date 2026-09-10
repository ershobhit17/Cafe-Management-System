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
  static const _kWeekResetKey = 'cafe_week_reset_timestamp';
  static const _kMonthResetKey = 'cafe_month_reset_timestamp';

  RealtimeChannel? _realtimeChannel;
  Timer? _pollingTimer;

  bool _isLoading = false;
  EarningsRange _selectedRange = EarningsRange.today;
  DateTimeRange? _customRange;
  String? _errorMessage;

  // Selected range metrics - all initialized to 0
  double _totalRevenue = 0.0;
  double _paidRevenue = 0.0;
  double _pendingRevenue = 0.0;
  int _totalOrders = 0;
  int _pendingOrdersCount = 0;
  double _averageOrderValue = 0.0;
  List<DailyEarningPoint> _chartPoints = [];

  // Dedicated period metrics - all strictly initialized to 0
  double _todayRevenue = 0.0;
  int _todayOrders = 0;
  double _weeklyRevenue = 0.0;
  int _weeklyOrders = 0;
  double _monthlyRevenue = 0.0;
  int _monthlyOrders = 0;

  DateTime? _shiftResetTime;
  DateTime? _weekResetTime;
  DateTime? _monthResetTime;

  bool get isLoading => _isLoading;
  EarningsRange get selectedRange => _selectedRange;
  DateTimeRange? get customRange => _customRange;
  String? get errorMessage => _errorMessage;

  double get totalRevenue => _totalRevenue;
  double get paidRevenue => _paidRevenue;
  double get pendingRevenue => _pendingRevenue;
  int get totalOrders => _totalOrders;
  int get pendingOrdersCount => _pendingOrdersCount;
  double get averageOrderValue => _averageOrderValue;
  List<DailyEarningPoint> get chartPoints => _chartPoints;

  double get todayRevenue => _todayRevenue;
  int get todayOrders => _todayOrders;
  double get weeklyRevenue => _weeklyRevenue;
  int get weeklyOrders => _weeklyOrders;
  double get monthlyRevenue => _monthlyRevenue;
  int get monthlyOrders => _monthlyOrders;

  DateTime? get shiftResetTime => _shiftResetTime;
  DateTime? get weekResetTime => _weekResetTime;
  DateTime? get monthResetTime => _monthResetTime;

  bool get hasActiveShiftReset => _shiftResetTime != null;
  bool get hasActiveWeekReset => _weekResetTime != null;
  bool get hasActiveMonthReset => _monthResetTime != null;
  bool get hasAnyActiveReset => hasActiveShiftReset || hasActiveWeekReset || hasActiveMonthReset;

  EarningsService() {
    _initShiftReset();
  }

  Future<void> _initShiftReset() async {
    final now = DateTime.now();
    try {
      // 1. Shift (Today) reset
      final savedShift = await _storage.read(key: _kShiftResetKey);
      if (savedShift != null) {
        final parsed = DateTime.tryParse(savedShift);
        if (parsed != null && parsed.year == now.year && parsed.month == now.month && parsed.day == now.day) {
          _shiftResetTime = parsed;
        } else {
          await _storage.delete(key: _kShiftResetKey);
        }
      }

      // 2. Week reset
      final savedWeek = await _storage.read(key: _kWeekResetKey);
      if (savedWeek != null) {
        final parsed = DateTime.tryParse(savedWeek);
        final currentWeekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        if (parsed != null && (parsed.isAfter(currentWeekStart) || parsed.isAtSameMomentAs(currentWeekStart))) {
          _weekResetTime = parsed;
        } else {
          await _storage.delete(key: _kWeekResetKey);
        }
      }

      // 3. Month reset
      final savedMonth = await _storage.read(key: _kMonthResetKey);
      if (savedMonth != null) {
        final parsed = DateTime.tryParse(savedMonth);
        if (parsed != null && parsed.year == now.year && parsed.month == now.month) {
          _monthResetTime = parsed;
        } else {
          await _storage.delete(key: _kMonthResetKey);
        }
      }
    } catch (_) {}
  }

  void subscribeToRealtimeEarnings(String cafeId, {bool isDemo = false}) {
    if (!SupabaseConfig.isConfigured || isDemo) return;

    _realtimeChannel?.unsubscribe();
    _realtimeChannel = Supabase.instance.client
        .channel('earnings_orders_channel_$cafeId')
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
            debugPrint('Realtime earnings event received: ${payload.eventType}');
            await fetchEarnings(cafeId, isDemo: isDemo);
          },
        )
        .subscribe();

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      fetchEarnings(cafeId, isDemo: isDemo);
    });
  }

  Future<void> resetTodayShift(String cafeId, {bool isDemo = false}) async {
    final now = DateTime.now();
    _shiftResetTime = now;
    try {
      await _storage.write(key: _kShiftResetKey, value: now.toIso8601String());
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<void> resetWeekCounter(String cafeId, {bool isDemo = false}) async {
    final now = DateTime.now();
    _weekResetTime = now;
    try {
      await _storage.write(key: _kWeekResetKey, value: now.toIso8601String());
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<void> resetMonthCounter(String cafeId, {bool isDemo = false}) async {
    final now = DateTime.now();
    _monthResetTime = now;
    try {
      await _storage.write(key: _kMonthResetKey, value: now.toIso8601String());
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<void> resetAllCounters(String cafeId, {bool isDemo = false}) async {
    final now = DateTime.now();
    _shiftResetTime = now;
    _weekResetTime = now;
    _monthResetTime = now;
    try {
      await _storage.write(key: _kShiftResetKey, value: now.toIso8601String());
      await _storage.write(key: _kWeekResetKey, value: now.toIso8601String());
      await _storage.write(key: _kMonthResetKey, value: now.toIso8601String());
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

  Future<void> restoreFullWeekView(String cafeId, {bool isDemo = false}) async {
    _weekResetTime = null;
    try {
      await _storage.delete(key: _kWeekResetKey);
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<void> restoreFullMonthView(String cafeId, {bool isDemo = false}) async {
    _monthResetTime = null;
    try {
      await _storage.delete(key: _kMonthResetKey);
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<void> restoreAllViews(String cafeId, {bool isDemo = false}) async {
    _shiftResetTime = null;
    _weekResetTime = null;
    _monthResetTime = null;
    try {
      await _storage.delete(key: _kShiftResetKey);
      await _storage.delete(key: _kWeekResetKey);
      await _storage.delete(key: _kMonthResetKey);
    } catch (_) {}
    await fetchEarnings(cafeId, isDemo: isDemo);
  }

  Future<bool> clearCafeOrdersDatabase(String cafeId, {bool isDemo = false}) async {
    try {
      if (SupabaseConfig.isConfigured && !isDemo) {
        await Supabase.instance.client
            .from('orders')
            .delete()
            .eq('cafe_id', cafeId);
      }
      await restoreAllViews(cafeId, isDemo: isDemo);
      return true;
    } catch (e) {
      debugPrint('Error clearing orders database: $e');
      return false;
    }
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
    final defaultMonthStart = DateTime(now.year, now.month, 1);
    final defaultWeekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final defaultTodayStart = DateTime(now.year, now.month, now.day);

    final monthStart = _monthResetTime ?? defaultMonthStart;
    final weekStart = _weekResetTime ?? defaultWeekStart;
    final todayStart = _shiftResetTime ?? defaultTodayStart;

    DateTime rangeStart;
    DateTime rangeEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedRange) {
      case EarningsRange.today:
        rangeStart = todayStart;
        break;
      case EarningsRange.thisWeek:
        rangeStart = weekStart;
        break;
      case EarningsRange.thisMonth:
        rangeStart = monthStart;
        break;
      case EarningsRange.custom:
        rangeStart = _customRange != null ? _customRange!.start : defaultTodayStart;
        rangeEnd = _customRange != null
            ? DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day, 23, 59, 59)
            : rangeEnd;
        break;
    }

    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 150));
      _applyZeroDemoEarnings(rangeStart, rangeEnd);
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final queryStart = rangeStart.isBefore(defaultMonthStart) ? rangeStart : defaultMonthStart;
      final queryEnd = rangeEnd.isAfter(now) ? rangeEnd : now.add(const Duration(hours: 1));

      final res = await Supabase.instance.client
          .from('orders')
          .select('id, status, total_amount, created_at')
          .eq('cafe_id', cafeId)
          .gte('created_at', queryStart.toIso8601String())
          .lte('created_at', queryEnd.toIso8601String())
          .order('created_at', ascending: true);

      final List ordersList = res as List;

      // Temporary accumulators - initialized to 0
      double todayPaidSum = 0.0;
      int todayPaidCount = 0;

      double weekPaidSum = 0.0;
      int weekPaidCount = 0;

      double monthPaidSum = 0.0;
      int monthPaidCount = 0;

      double selectedPaidSum = 0.0;
      int selectedPaidCount = 0;

      double selectedPendingSum = 0.0;
      int selectedPendingCount = 0;

      final Map<String, List<double>> dayMap = {};

      for (var row in ordersList) {
        final amt = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
        final status = (row['status'] as String?)?.toLowerCase() ?? 'pending';
        final dt = DateTime.tryParse(row['created_at'] as String)?.toLocal() ?? DateTime.now();

        // Skip cancelled/rejected orders
        if (status == 'cancelled' || status == 'rejected') continue;

        final isPaid = status == 'paid';

        // Month-to-date calculation (ONLY PAID ORDERS COUNT AS REVENUE)
        if (dt.isAfter(monthStart) || dt.isAtSameMomentAs(monthStart)) {
          if (isPaid) {
            monthPaidSum += amt;
            monthPaidCount++;
          }
        }

        // Week-to-date calculation (ONLY PAID ORDERS COUNT AS REVENUE)
        if (dt.isAfter(weekStart) || dt.isAtSameMomentAs(weekStart)) {
          if (isPaid) {
            weekPaidSum += amt;
            weekPaidCount++;
          }
        }

        // Today calculation (ONLY PAID ORDERS COUNT AS REVENUE)
        if (dt.isAfter(todayStart) || dt.isAtSameMomentAs(todayStart)) {
          if (isPaid) {
            todayPaidSum += amt;
            todayPaidCount++;
          }
        }

        // Selected Range calculation
        final inSelectedRange = (dt.isAfter(rangeStart) || dt.isAtSameMomentAs(rangeStart)) &&
            (dt.isBefore(rangeEnd) || dt.isAtSameMomentAs(rangeEnd));

        if (inSelectedRange) {
          if (isPaid) {
            selectedPaidSum += amt;
            selectedPaidCount++;

            // Only add to day breakdown chart if PAID
            final dateKey = DateFormat('yyyy-MM-dd').format(dt);
            dayMap.putIfAbsent(dateKey, () => []).add(amt);
          } else {
            selectedPendingSum += amt;
            selectedPendingCount++;
          }
        }
      }

      // Assign period metrics (strictly paid revenue)
      _todayRevenue = todayPaidSum;
      _todayOrders = todayPaidCount;
      _weeklyRevenue = weekPaidSum;
      _weeklyOrders = weekPaidCount;
      _monthlyRevenue = monthPaidSum;
      _monthlyOrders = monthPaidCount;

      // Assign selected range metrics
      _totalRevenue = selectedPaidSum;
      _paidRevenue = selectedPaidSum;
      _pendingRevenue = selectedPendingSum;
      _totalOrders = selectedPaidCount;
      _pendingOrdersCount = selectedPendingCount;
      _averageOrderValue = selectedPaidCount > 0 ? selectedPaidSum / selectedPaidCount : 0.0;

      // Build daily chart points
      _chartPoints = [];
      final daysCount = rangeEnd.difference(rangeStart).inDays + 1;
      final displayLimit = daysCount > 31 ? 31 : (daysCount < 1 ? 1 : daysCount);

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
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applyZeroDemoEarnings(DateTime start, DateTime end) {
    // Zero initialize all counters as requested
    _todayRevenue = 0.0;
    _todayOrders = 0;
    _weeklyRevenue = 0.0;
    _weeklyOrders = 0;
    _monthlyRevenue = 0.0;
    _monthlyOrders = 0;

    _totalRevenue = 0.0;
    _paidRevenue = 0.0;
    _pendingRevenue = 0.0;
    _totalOrders = 0;
    _pendingOrdersCount = 0;
    _averageOrderValue = 0.0;

    _chartPoints = [];
    final daysCount = end.difference(start).inDays + 1;
    final displayLimit = daysCount > 31 ? 31 : daysCount;
    for (int i = 0; i < displayLimit; i++) {
      final d = start.add(Duration(days: i));
      _chartPoints.add(DailyEarningPoint(date: d, amount: 0.0, orderCount: 0));
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

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
}
