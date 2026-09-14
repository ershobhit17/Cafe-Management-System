class PlatformMetrics {
  final int totalCafes;
  final int pendingApprovals;
  final int totalOrders;
  final double totalRevenue;

  const PlatformMetrics({
    required this.totalCafes,
    required this.pendingApprovals,
    required this.totalOrders,
    required this.totalRevenue,
  });

  factory PlatformMetrics.fromJson(Map<String, dynamic> json) {
    final rawRev = json['total_revenue'];
    final rev = rawRev is num
        ? rawRev.toDouble()
        : (double.tryParse(rawRev?.toString() ?? '') ?? 0.0);
    return PlatformMetrics(
      totalCafes: json['total_cafes'] is num
          ? (json['total_cafes'] as num).toInt()
          : (int.tryParse(json['total_cafes']?.toString() ?? '') ?? 0),
      pendingApprovals: json['pending_approvals'] is num
          ? (json['pending_approvals'] as num).toInt()
          : (int.tryParse(json['pending_approvals']?.toString() ?? '') ?? 0),
      totalOrders: json['total_orders'] is num
          ? (json['total_orders'] as num).toInt()
          : (int.tryParse(json['total_orders']?.toString() ?? '') ?? 0),
      totalRevenue: rev,
    );
  }
}

class CafeOverviewAdmin {
  final String cafeId;
  final String cafeName;
  final String? ownerId;
  final String ownerEmail;
  final bool isSuspended;
  final String? suspendedReason;
  final DateTime? createdAt;
  final String tier;
  final String status;
  final bool isTrial;
  final int daysRemaining;
  final DateTime? endDate;
  final int tablesCount;
  final int maxTables;
  final int itemsCount;
  final int maxItems;
  final int ordersCount;
  final double totalRevenue;

  const CafeOverviewAdmin({
    required this.cafeId,
    required this.cafeName,
    this.ownerId,
    required this.ownerEmail,
    required this.isSuspended,
    this.suspendedReason,
    this.createdAt,
    required this.tier,
    required this.status,
    required this.isTrial,
    required this.daysRemaining,
    this.endDate,
    required this.tablesCount,
    required this.maxTables,
    required this.itemsCount,
    required this.maxItems,
    required this.ordersCount,
    required this.totalRevenue,
  });

  factory CafeOverviewAdmin.fromJson(Map<String, dynamic> json) {
    return CafeOverviewAdmin(
      cafeId: (json['cafe_id'] ?? '') as String,
      cafeName: (json['cafe_name'] ?? 'Unnamed Cafe') as String,
      ownerId: json['owner_id'] as String?,
      ownerEmail: (json['owner_email'] ?? 'No email linked') as String,
      isSuspended: (json['is_suspended'] as bool?) ?? false,
      suspendedReason: json['suspended_reason'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      tier: (json['tier'] ?? 'TRIAL').toString().toUpperCase(),
      status: (json['status'] ?? 'ACTIVE').toString().toUpperCase(),
      isTrial: (json['is_trial'] as bool?) ?? false,
      daysRemaining: json['days_remaining'] is num
          ? (json['days_remaining'] as num).toInt()
          : (int.tryParse(json['days_remaining']?.toString() ?? '') ?? 0),
      endDate: json['end_date'] != null ? DateTime.tryParse(json['end_date'].toString()) : null,
      tablesCount: json['tables_count'] is num
          ? (json['tables_count'] as num).toInt()
          : (int.tryParse(json['tables_count']?.toString() ?? '') ?? 0),
      maxTables: json['max_tables'] is num
          ? (json['max_tables'] as num).toInt()
          : (int.tryParse(json['max_tables']?.toString() ?? '') ?? 5),
      itemsCount: json['items_count'] is num
          ? (json['items_count'] as num).toInt()
          : (int.tryParse(json['items_count']?.toString() ?? '') ?? 0),
      maxItems: json['max_items'] is num
          ? (json['max_items'] as num).toInt()
          : (int.tryParse(json['max_items']?.toString() ?? '') ?? 30),
      ordersCount: json['orders_count'] is num
          ? (json['orders_count'] as num).toInt()
          : (int.tryParse(json['orders_count']?.toString() ?? '') ?? 0),
      totalRevenue: json['total_revenue'] is num
          ? (json['total_revenue'] as num).toDouble()
          : (double.tryParse(json['total_revenue']?.toString() ?? '') ?? 0.0),
    );
  }

  bool get isExpiringSoon => daysRemaining <= 3 && daysRemaining > 0;
  bool get isExpired => daysRemaining <= 0;

  String get formattedTierDisplay {
    if (isTrial) return '7-Day Free Trial';
    switch (tier) {
      case 'GROWTH':
        return 'Growth Plan (₹799)';
      case 'ENTERPRISE':
        return 'Enterprise (₹1,499)';
      case 'STARTER':
      default:
        return 'Starter Plan (₹399)';
    }
  }
}

class AdminUserInfo {
  final String email;
  final String role;
  final DateTime? createdAt;

  const AdminUserInfo({
    required this.email,
    required this.role,
    this.createdAt,
  });

  factory AdminUserInfo.fromJson(Map<String, dynamic> json) {
    return AdminUserInfo(
      email: (json['email'] ?? '') as String,
      role: (json['role'] ?? 'admin') as String,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }
}
