class SubscriptionTierInfo {
  final String id;
  final String name;
  final double price;
  final int maxTables; // -1 for unlimited
  final int maxMenuItems; // -1 for unlimited
  final String description;
  final List<String> features;
  final bool isPopular;

  const SubscriptionTierInfo({
    required this.id,
    required this.name,
    required this.price,
    required this.maxTables,
    required this.maxMenuItems,
    required this.description,
    required this.features,
    this.isPopular = false,
  });

  static const starter = SubscriptionTierInfo(
    id: 'STARTER',
    name: 'Starter Plan',
    price: 399,
    maxTables: 5,
    maxMenuItems: 30,
    description: 'Perfect for small cafes & boutique coffee bars starting out.',
    features: [
      'Up to 5 Dining Tables & QR Codes',
      'Up to 30 Active Menu Items',
      'Realtime Kitchen Live Orders',
      'Customer Web Menu & Live Status',
      'Daily Earnings Summary',
    ],
  );

  static const growth = SubscriptionTierInfo(
    id: 'GROWTH',
    name: 'Growth Plan',
    price: 799,
    maxTables: 20,
    maxMenuItems: 70,
    isPopular: true,
    description: 'Ideal for busy cafes, casual bistros and growing restaurants.',
    features: [
      'Up to 20 Dining Tables & QR Codes',
      'Up to 70 Active Menu Items',
      'Kitchen Display System (KDS)',
      '1-Click 80mm/58mm Thermal KOT Print',
      'Category Navigation & Offer Pricing',
      'Daily / Weekly / Monthly Analytics',
    ],
  );

  static const enterprise = SubscriptionTierInfo(
    id: 'ENTERPRISE',
    name: 'Enterprise / Pro',
    price: 1499,
    maxTables: -1,
    maxMenuItems: -1,
    description: 'For high-volume restaurants & multi-section dining spaces.',
    features: [
      'Unlimited Dining Tables & QRs',
      'Unlimited Menu Items & Categories',
      'Full Kitchen Display System (KDS)',
      'Instant Thermal KOT Printing',
      'Priority Phone & WhatsApp Support',
      'Dedicated Account Onboarding',
    ],
  );

  static const trial = SubscriptionTierInfo(
    id: 'TRIAL',
    name: '7-Day Free Trial',
    price: 0,
    maxTables: 5,
    maxMenuItems: 30,
    description: 'Complimentary 7-day all-access trial to evaluate SnapServe.',
    features: [
      'Up to 5 Dining Tables & QR Codes',
      'Up to 30 Active Menu Items',
      'Realtime Kitchen Live Orders & KDS',
      'Thermal KOT Printing & Bill Settlement',
      'Customer Web QR Menu',
    ],
  );

  static const List<SubscriptionTierInfo> allTiers = [starter, growth, enterprise];

  static SubscriptionTierInfo getTierById(String id) {
    switch (id.toUpperCase()) {
      case 'TRIAL':
        return trial;
      case 'GROWTH':
        return growth;
      case 'ENTERPRISE':
        return enterprise;
      default:
        return starter;
    }
  }
}

class SubscriptionOverview {
  final String tier; // 'TRIAL', 'STARTER', 'GROWTH', 'ENTERPRISE'
  final String status; // 'ACTIVE', 'ACTIVE_TRIAL', 'EXPIRED_TRIAL', 'PENDING_APPROVAL', 'EXPIRED'
  final bool isTrial;
  final DateTime startDate;
  final DateTime endDate;
  final int daysRemaining;
  final int tablesUsed;
  final int maxTables; // -1 for unlimited
  final int itemsUsed;
  final int maxItems; // -1 for unlimited
  final String? utrNumber;
  final double amountPaid;
  final bool hasPendingApproval;
  final String? pendingTier;
  final String? pendingUtr;
  final double? pendingAmount;

  SubscriptionOverview({
    required this.tier,
    required this.status,
    this.isTrial = false,
    required this.startDate,
    required this.endDate,
    required this.daysRemaining,
    required this.tablesUsed,
    required this.maxTables,
    required this.itemsUsed,
    required this.maxItems,
    this.utrNumber,
    required this.amountPaid,
    this.hasPendingApproval = false,
    this.pendingTier,
    this.pendingUtr,
    this.pendingAmount,
  });

  factory SubscriptionOverview.fromJson(Map<String, dynamic> json) {
    final t = (json['tier'] as String? ?? 'TRIAL').toUpperCase();
    final s = (json['status'] as String? ?? 'ACTIVE_TRIAL').toUpperCase();
    final bool trial = (json['is_trial'] as bool?) ?? (t == 'TRIAL' || s.contains('TRIAL'));

    return SubscriptionOverview(
      tier: t,
      status: s,
      isTrial: trial,
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date']) ?? DateTime.now()
          : DateTime.now(),
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date']) ?? DateTime.now().add(const Duration(days: 7))
          : DateTime.now().add(const Duration(days: 7)),
      daysRemaining: json['days_remaining'] is num
          ? (json['days_remaining'] as num).toInt()
          : (int.tryParse(json['days_remaining']?.toString() ?? '') ?? 7),
      tablesUsed: json['tables_used'] is num
          ? (json['tables_used'] as num).toInt()
          : (int.tryParse(json['tables_used']?.toString() ?? '') ?? 0),
      maxTables: json['max_tables'] is num
          ? (json['max_tables'] as num).toInt()
          : (int.tryParse(json['max_tables']?.toString() ?? '') ?? 5),
      itemsUsed: json['items_used'] is num
          ? (json['items_used'] as num).toInt()
          : (int.tryParse(json['items_used']?.toString() ?? '') ?? 0),
      maxItems: json['max_items'] is num
          ? (json['max_items'] as num).toInt()
          : (int.tryParse(json['max_items']?.toString() ?? '') ?? 30),
      utrNumber: json['utr_number'] as String?,
      amountPaid: json['amount_paid'] is num
          ? (json['amount_paid'] as num).toDouble()
          : (double.tryParse(json['amount_paid']?.toString() ?? '') ?? 0.0),
      hasPendingApproval: (json['has_pending_approval'] as bool?) ?? false,
      pendingTier: json['pending_tier'] as String?,
      pendingUtr: json['pending_utr'] as String?,
      pendingAmount: json['pending_amount'] is num
          ? (json['pending_amount'] as num).toDouble()
          : (double.tryParse(json['pending_amount']?.toString() ?? '')),
    );
  }

  factory SubscriptionOverview.defaultTrial({int tables = 0, int items = 0, int daysLeft = 7}) {
    return SubscriptionOverview(
      tier: 'TRIAL',
      status: daysLeft > 0 ? 'ACTIVE_TRIAL' : 'EXPIRED_TRIAL',
      isTrial: true,
      startDate: DateTime.now(),
      endDate: DateTime.now().add(Duration(days: daysLeft)),
      daysRemaining: daysLeft,
      tablesUsed: tables,
      maxTables: 5,
      itemsUsed: items,
      maxItems: 30,
      amountPaid: 0.0,
    );
  }

  factory SubscriptionOverview.defaultStarter({int tables = 0, int items = 0}) {
    return SubscriptionOverview.defaultTrial(tables: tables, items: items, daysLeft: 7);
  }

  SubscriptionTierInfo get tierInfo => SubscriptionTierInfo.getTierById(tier);

  bool get isEnterprise => tier == 'ENTERPRISE' || maxTables == -1;
  bool get isTrialExpired => status == 'EXPIRED_TRIAL' || (isTrial && daysRemaining <= 0);
  bool get isSubscriptionExpired => status == 'EXPIRED' || isTrialExpired;

  bool get isTablesLimitReached => isTrialExpired || (!isEnterprise && tablesUsed >= maxTables);
  bool get isItemsLimitReached => isTrialExpired || (!isEnterprise && itemsUsed >= maxItems);

  double get tablesUsageFraction {
    if (isEnterprise || maxTables <= 0) return 0.0;
    return (tablesUsed / maxTables).clamp(0.0, 1.0);
  }

  double get itemsUsageFraction {
    if (isEnterprise || maxItems <= 0) return 0.0;
    return (itemsUsed / maxItems).clamp(0.0, 1.0);
  }

  String get tablesUsageText {
    if (isEnterprise) return '$tablesUsed Tables (Unlimited)';
    return '$tablesUsed/$maxTables Tables used';
  }

  String get itemsUsageText {
    if (isEnterprise) return '$itemsUsed Items (Unlimited)';
    return '$itemsUsed/$maxItems Items used';
  }
}
