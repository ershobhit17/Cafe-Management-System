import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/super_admin_model.dart';

class SuperAdminService extends ChangeNotifier {
  PlatformMetrics? _metrics;
  List<CafeOverviewAdmin> _allCafes = [];
  List<Map<String, dynamic>> _pendingApprovals = [];
  List<AdminUserInfo> _adminUsers = [];

  bool _isLoading = false;
  String? _errorMessage;
  String? _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL, TRIAL, ACTIVE, EXPIRING_SOON, EXPIRED, SUSPENDED

  PlatformMetrics? get metrics => _metrics;
  List<CafeOverviewAdmin> get allCafes => _allCafes;
  List<Map<String, dynamic>> get pendingApprovals => _pendingApprovals;
  List<AdminUserInfo> get adminUsers => _adminUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery ?? '';
  String get statusFilter => _statusFilter;

  List<CafeOverviewAdmin> get filteredCafes {
    return _allCafes.where((cafe) {
      // Search text match
      final q = (_searchQuery ?? '').toLowerCase().trim();
      final matchesSearch = q.isEmpty ||
          cafe.cafeName.toLowerCase().contains(q) ||
          cafe.ownerEmail.toLowerCase().contains(q) ||
          cafe.tier.toLowerCase().contains(q);

      if (!matchesSearch) return false;

      // Status filter
      switch (_statusFilter) {
        case 'TRIAL':
          return cafe.isTrial && !cafe.isSuspended;
        case 'ACTIVE':
          return !cafe.isTrial && !cafe.isExpired && !cafe.isSuspended;
        case 'EXPIRING_SOON':
          return cafe.isExpiringSoon && !cafe.isSuspended;
        case 'EXPIRED':
          return cafe.isExpired && !cafe.isSuspended;
        case 'SUSPENDED':
          return cafe.isSuspended;
        case 'ALL':
        default:
          return true;
      }
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(String filter) {
    _statusFilter = filter;
    notifyListeners();
  }

  /// Refreshes all Super Admin data systematically
  Future<void> refreshAll() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await Future.wait([
        fetchPlatformMetrics(),
        fetchAllCafes(),
        fetchPendingApprovals(),
        fetchAdminUsers(),
      ]);
    } catch (e) {
      _errorMessage = 'Failed to load platform data: $e';
      debugPrint('SuperAdminService refreshAll error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPlatformMetrics() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final res = await Supabase.instance.client.rpc('admin_get_platform_metrics');
      if (res is Map) {
        _metrics = PlatformMetrics.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('fetchPlatformMetrics error: $e');
    }
  }

  Future<void> fetchAllCafes() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final res = await Supabase.instance.client.rpc('admin_get_all_cafes_overview');
      if (res is List) {
        _allCafes = res
            .map((e) => CafeOverviewAdmin.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('fetchAllCafes error: $e');
    }
  }

  Future<void> fetchPendingApprovals() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final res = await Supabase.instance.client.rpc('get_pending_subscriptions');
      if (res is List) {
        _pendingApprovals = res
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint('fetchPendingApprovals error: $e');
    }
  }

  Future<void> fetchAdminUsers() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final res = await Supabase.instance.client.rpc('admin_list_admins');
      if (res is List) {
        _adminUsers = res
            .map((e) => AdminUserInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('fetchAdminUsers error: $e');
    }
  }

  /// Grant or extend subscription for a cafe
  Future<Map<String, dynamic>> grantSubscription({
    required String cafeId,
    required String tier,
    required int days,
    String? notes,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_grant_subscription',
        params: {
          'p_cafe_id': cafeId,
          'p_tier': tier,
          'p_days': days,
          'p_notes': notes ?? 'Granted by Super Admin',
        },
      );

      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] == true) {
        await refreshAll();
      }
      return map;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Suspend or restore cafe access
  Future<Map<String, dynamic>> toggleCafeAccess({
    required String cafeId,
    required bool isSuspended,
    String? reason,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_update_cafe_access',
        params: {
          'p_cafe_id': cafeId,
          'p_is_suspended': isSuspended,
          'p_reason': reason,
        },
      );

      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] == true) {
        await refreshAll();
      }
      return map;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Approve pending subscription payment
  Future<Map<String, dynamic>> approveSubscription(String subscriptionId) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'approve_subscription',
        params: {'p_subscription_id': subscriptionId},
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] == true) {
        await refreshAll();
      }
      return map;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Reject pending subscription payment
  Future<Map<String, dynamic>> rejectSubscription(String subscriptionId, {String? reason}) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'reject_subscription',
        params: {
          'p_subscription_id': subscriptionId,
          'p_reason': reason ?? 'Payment details not verified',
        },
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] == true) {
        await refreshAll();
      }
      return map;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Add new Admin
  Future<Map<String, dynamic>> addAdmin(String email, {String role = 'admin'}) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_add_admin',
        params: {
          'p_email': email.trim().toLowerCase(),
          'p_role': role,
        },
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] == true) {
        await fetchAdminUsers();
        notifyListeners();
      }
      return map;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Revoke Admin
  Future<Map<String, dynamic>> removeAdmin(String email) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_remove_admin',
        params: {'p_email': email.trim().toLowerCase()},
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] == true) {
        await fetchAdminUsers();
        notifyListeners();
      }
      return map;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
