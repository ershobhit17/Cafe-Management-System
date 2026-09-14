import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/subscription_model.dart';
import '../../services/auth_service.dart';
import '../../services/cafe_service.dart';
import '../../services/menu_service.dart';
import '../../services/subscription_service.dart';
import 'phonepe_payment_dialog.dart';

class SubscriptionPlansScreen extends StatefulWidget {
  const SubscriptionPlansScreen({super.key});

  @override
  State<SubscriptionPlansScreen> createState() => _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final auth = context.read<AuthService>();
    final cafeService = context.read<CafeService>();
    final menuService = context.read<MenuService>();
    final subService = context.read<SubscriptionService>();

    subService.fetchSubscriptionOverview(
      auth.currentCafeId,
      isDemo: auth.isDemoMode,
      currentTablesCount: cafeService.tables.length,
      currentItemsCount: menuService.items.length,
    );
  }

  void _openPaymentDialog(SubscriptionTierInfo tier) async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PhonePePaymentDialog(tier: tier),
    );

    if (success == true && mounted) {
      _loadData();
    }
  }

  Color _getProgressColor(double frac) {
    if (frac >= 1.0) return Colors.red.shade700;
    if (frac >= 0.8) return Colors.orange.shade800;
    return const Color(0xFFFF7A00);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final subService = context.watch<SubscriptionService>();
    final overview = subService.overview ?? SubscriptionOverview.defaultStarter();

    const primaryColor = Color(0xFFFF7A00);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              auth.currentCafeName.isNotEmpty ? auth.currentCafeName : 'SnapServe Cafe',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const Text('Upgrade & Expand Plan', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: _loadData,
          ),
        ],
      ),
      body: subService.isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : RefreshIndicator(
              color: primaryColor,
              onRefresh: () async => _loadData(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  // Active Plan Overview Card
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: primaryColor.withValues(alpha: 0.3), width: 1.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        overview.isTrial ? Icons.hourglass_top : Icons.verified,
                                        color: overview.isTrialExpired ? Colors.red : primaryColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        overview.isTrial
                                            ? (overview.isTrialExpired ? 'Free Trial Expired' : '7-Day Free Trial')
                                            : overview.tierInfo.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: overview.isTrialExpired ? Colors.red.shade800 : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    overview.isTrialExpired
                                        ? 'Trial ended on ${DateFormat('dd MMM yyyy').format(overview.endDate)}. Upgrade required.'
                                        : (overview.isTrial
                                            ? 'Trial ends: ${DateFormat('dd MMM yyyy').format(overview.endDate)} (${overview.daysRemaining} days left)'
                                            : 'Renewal: ${DateFormat('dd MMM yyyy').format(overview.endDate)} (${overview.daysRemaining} days left)'),
                                    style: TextStyle(
                                      color: overview.isTrialExpired ? Colors.red.shade700 : Colors.grey.shade600,
                                      fontSize: 12,
                                      fontWeight: overview.isTrialExpired ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: overview.isTrialExpired
                                      ? Colors.red.shade50
                                      : (overview.isTrial ? Colors.amber.shade50 : Colors.green.shade50),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: overview.isTrialExpired
                                        ? Colors.red.shade300
                                        : (overview.isTrial ? Colors.amber.shade400 : Colors.green.shade300),
                                  ),
                                ),
                                child: Text(
                                  overview.isTrialExpired
                                      ? 'EXPIRED'
                                      : (overview.isTrial ? 'FREE TRIAL' : overview.status),
                                  style: TextStyle(
                                    color: overview.isTrialExpired
                                        ? Colors.red.shade900
                                        : (overview.isTrial ? Colors.amber.shade900 : Colors.green.shade800),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Usage Quota Meters
                          const Text(
                            'Current Resource Quotas',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 12),

                          // Tables Meter
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.table_restaurant, size: 16, color: primaryColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    overview.tablesUsageText,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ],
                              ),
                              if (!overview.isEnterprise)
                                Text(
                                  '${(overview.tablesUsageFraction * 100).toInt()}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _getProgressColor(overview.tablesUsageFraction),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: overview.isEnterprise ? 0.15 : overview.tablesUsageFraction,
                            color: _getProgressColor(overview.tablesUsageFraction),
                            backgroundColor: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 7,
                          ),

                          const SizedBox(height: 16),

                          // Menu Items Meter
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.restaurant_menu, size: 16, color: primaryColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    overview.itemsUsageText,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ],
                              ),
                              if (!overview.isEnterprise)
                                Text(
                                  '${(overview.itemsUsageFraction * 100).toInt()}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _getProgressColor(overview.itemsUsageFraction),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: overview.isEnterprise ? 0.15 : overview.itemsUsageFraction,
                            color: _getProgressColor(overview.itemsUsageFraction),
                            backgroundColor: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 7,
                          ),

                          if (overview.isTablesLimitReached || overview.isItemsLimitReached) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      overview.isTablesLimitReached
                                          ? 'Table quota reached! Upgrade to Growth or Enterprise to add more tables.'
                                          : 'Menu item quota reached! Upgrade your plan to add more dishes.',
                                      style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Pending Approval Alert Banner
                  if (overview.hasPendingApproval) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB), // Amber 50
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Plan Upgrade Under Verification',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Upgrade request submitted for ${overview.pendingTier?.toUpperCase()} Plan (UTR: ${overview.pendingUtr ?? "Submitted"}).',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Super Admin is verifying your payment against the bank statement. Your current active plan limits remain in effect until approved.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade900,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Text(
                    'Available Subscription Plans',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Upgrade your plan to unlock more dining tables and menu items.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  // Plans Matrix Cards
                  ...SubscriptionTierInfo.allTiers.map((tier) {
                    final isCurrentTier = overview.tier == tier.id && !overview.isTrial;
                    final isPendingTier = overview.hasPendingApproval &&
                        overview.pendingTier?.toUpperCase() == tier.id.toUpperCase();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: tier.isPopular ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isCurrentTier
                              ? Colors.green
                              : isPendingTier
                                  ? const Color(0xFFF59E0B)
                                  : tier.isPopular
                                      ? primaryColor
                                      : Colors.grey.shade300,
                          width: tier.isPopular || isCurrentTier || isPendingTier ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          tier.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                        ),
                                        if (isPendingTier) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD97706),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'APPROVAL PENDING',
                                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ] else if (tier.isPopular) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: primaryColor,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'POPULAR',
                                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      tier.description,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${tier.price.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: isCurrentTier ? Colors.green.shade800 : primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 22,
                                      ),
                                    ),
                                    const Text('/month', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 20),

                            // Features List
                            ...tier.features.map(
                              (feat) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        feat,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Action Button
                            SizedBox(
                              width: double.infinity,
                              child: isCurrentTier
                                  ? OutlinedButton.icon(
                                      onPressed: null,
                                      icon: const Icon(Icons.check, color: Colors.green),
                                      label: const Text('Current Active Plan', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Colors.green),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    )
                                  : isPendingTier
                                      ? OutlinedButton.icon(
                                          onPressed: () => _openPaymentDialog(tier),
                                          icon: const Icon(Icons.hourglass_top, size: 18, color: Color(0xFFD97706)),
                                          label: Text(
                                            'Awaiting Approval (UTR: ${overview.pendingUtr})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFFD97706), width: 1.5),
                                            backgroundColor: const Color(0xFFFFFBEB),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        )
                                      : ElevatedButton.icon(
                                          onPressed: () => _openPaymentDialog(tier),
                                          icon: const Icon(Icons.flash_on, size: 18),
                                          label: Text(
                                            'Upgrade to ${tier.name} (₹${tier.price.toStringAsFixed(0)})',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
