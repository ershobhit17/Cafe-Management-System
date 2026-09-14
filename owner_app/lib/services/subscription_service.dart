import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/subscription_model.dart';

class SubscriptionService extends ChangeNotifier {
  SubscriptionOverview? _overview;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  RealtimeChannel? _subChannel;

  SubscriptionOverview? get overview => _overview;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  Future<void> fetchSubscriptionOverview(
    String cafeId, {
    bool isDemo = false,
    int currentTablesCount = 0,
    int currentItemsCount = 0,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 250));
      // In demo mode, preserve existing tier if already upgraded, else default to STARTER
      final currentTier = _overview?.tier ?? 'STARTER';
      final tierInfo = SubscriptionTierInfo.getTierById(currentTier);

      _overview = SubscriptionOverview(
        tier: currentTier,
        status: _overview?.status ?? 'ACTIVE',
        startDate: _overview?.startDate ?? DateTime.now(),
        endDate: _overview?.endDate ?? DateTime.now().add(const Duration(days: 30)),
        daysRemaining: _overview?.daysRemaining ?? 30,
        tablesUsed: currentTablesCount > 0 ? currentTablesCount : (_overview?.tablesUsed ?? 5),
        maxTables: tierInfo.maxTables,
        itemsUsed: currentItemsCount > 0 ? currentItemsCount : (_overview?.itemsUsed ?? 10),
        maxItems: tierInfo.maxMenuItems,
        amountPaid: tierInfo.price,
      );
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final res = await Supabase.instance.client.rpc(
        'get_cafe_subscription_overview',
        params: {'p_cafe_id': cafeId},
      );

      if (res is Map) {
        _overview = SubscriptionOverview.fromJson(Map<String, dynamic>.from(res));
      } else {
        _overview = SubscriptionOverview.defaultStarter(
          tables: currentTablesCount,
          items: currentItemsCount,
        );
      }
      _errorMessage = null;
    } catch (e) {
      debugPrint('fetchSubscriptionOverview error: $e');
      _overview ??= SubscriptionOverview.defaultStarter(
        tables: currentTablesCount,
        items: currentItemsCount,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> submitUtrPayment({
    required String cafeId,
    required String tier,
    required String utrNumber,
    required double amount,
    bool isDemo = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    final cleanUtr = utrNumber.trim();
    if (cleanUtr.length < 10) {
      _isLoading = false;
      _errorMessage = 'Please enter a valid 12-digit Bank UTR / Transaction Reference Number.';
      notifyListeners();
      return {'success': false, 'error': _errorMessage};
    }

    // Check offline/demo mode
    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 600));
      final currentTier = _overview?.tier ?? 'STARTER';
      final currentTierInfo = SubscriptionTierInfo.getTierById(currentTier);

      _overview = SubscriptionOverview(
        tier: currentTier,
        status: _overview?.status ?? 'ACTIVE',
        isTrial: _overview?.isTrial ?? false,
        startDate: _overview?.startDate ?? DateTime.now(),
        endDate: _overview?.endDate ?? DateTime.now().add(const Duration(days: 30)),
        daysRemaining: _overview?.daysRemaining ?? 30,
        tablesUsed: _overview?.tablesUsed ?? 5,
        maxTables: currentTierInfo.maxTables,
        itemsUsed: _overview?.itemsUsed ?? 10,
        maxItems: currentTierInfo.maxMenuItems,
        utrNumber: _overview?.utrNumber,
        amountPaid: _overview?.amountPaid ?? currentTierInfo.price,
        hasPendingApproval: true,
        pendingTier: tier,
        pendingUtr: cleanUtr,
        pendingAmount: amount,
      );

      _isLoading = false;
      _successMessage = 'Payment submitted! UTR #$cleanUtr is pending Super Admin approval.';
      notifyListeners();
      return {
        'success': true,
        'message': _successMessage,
        'tier': tier,
      };
    }

    try {
      final res = await Supabase.instance.client.rpc(
        'submit_subscription_payment',
        params: {
          'p_cafe_id': cafeId,
          'p_tier': tier,
          'p_utr_number': cleanUtr,
          'p_amount': amount,
        },
      );

      final mapRes = Map<String, dynamic>.from(res as Map);
      if (mapRes['success'] == true) {
        _successMessage = mapRes['message'] as String? ?? 'Payment verified successfully!';
        // Re-fetch overview to reflect active tier limits in DB
        await fetchSubscriptionOverview(cafeId, isDemo: false);
        return mapRes;
      } else {
        _errorMessage = mapRes['error'] as String? ?? 'Failed to verify payment.';
        notifyListeners();
        return mapRes;
      }
    } catch (e) {
      _errorMessage = 'Payment verification error: $e';
      notifyListeners();
      return {'success': false, 'error': _errorMessage};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void subscribeToRealtimeSubscription(String cafeId, {bool isDemo = false}) {
    if (isDemo || !SupabaseConfig.isConfigured) return;

    _subChannel?.unsubscribe();
    _subChannel = Supabase.instance.client
        .channel('subscriptions_channel_$cafeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'cafe_id',
            value: cafeId,
          ),
          callback: (_) {
            fetchSubscriptionOverview(cafeId, isDemo: false);
          },
        )
        .subscribe();
  }

  // --------------------------------------------------------------------------
  // Admin Approval Methods
  // --------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchPendingSubscriptions({bool isDemo = false}) async {
    if (isDemo || !SupabaseConfig.isConfigured) {
      return [];
    }

    try {
      final res = await Supabase.instance.client.rpc('get_pending_subscriptions');
      if (res is List) {
        return List<Map<String, dynamic>>.from(
          res.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      debugPrint('fetchPendingSubscriptions error: $e');
      return [];
    }
  }

  Future<bool> approveSubscription(String subscriptionId, {bool isDemo = false}) async {
    if (isDemo || !SupabaseConfig.isConfigured) return true;

    try {
      final res = await Supabase.instance.client.rpc(
        'approve_subscription',
        params: {'p_subscription_id': subscriptionId},
      );
      return (res as Map?)?['success'] == true;
    } catch (e) {
      debugPrint('approveSubscription error: $e');
      return false;
    }
  }

  Future<bool> rejectSubscription(String subscriptionId, {String? reason, bool isDemo = false}) async {
    if (isDemo || !SupabaseConfig.isConfigured) return true;

    try {
      final res = await Supabase.instance.client.rpc(
        'reject_subscription',
        params: {
          'p_subscription_id': subscriptionId,
          'p_reason': reason,
        },
      );
      return (res as Map?)?['success'] == true;
    } catch (e) {
      debugPrint('rejectSubscription error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _subChannel?.unsubscribe();
    super.dispose();
  }
}
