import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/super_admin_model.dart';
import '../../services/auth_service.dart';
import '../../services/super_admin_service.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SuperAdminService>().refreshAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final adminService = context.watch<SuperAdminService>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101014) : const Color(0xFFF4F6F9),
      appBar: AppBar(
        elevation: 1,
        backgroundColor: isDark ? const Color(0xFF181820) : Colors.white,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7A00).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/images/app_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.admin_panel_settings, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Snap Serve',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.3)),
                      ),
                      child: const Text(
                        'SUPER ADMIN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1976D2),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  auth.currentUser?.email ?? 'ershobhit17@gmail.com',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh All Data',
            icon: const Icon(Icons.refresh),
            onPressed: () => adminService.refreshAll(),
          ),
          // Switch to Cafe Owner View
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF7A00),
                side: const BorderSide(color: Color(0xFFFF7A00)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(Icons.storefront, size: 16),
              label: const Text('My Cafe View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: () {
                auth.setSuperAdminViewMode(false);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => _confirmSignOut(context),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF7A00),
          labelColor: const Color(0xFFFF7A00),
          unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(
              icon: const Icon(Icons.restaurant, size: 18),
              text: 'Cafes & Plans (${adminService.allCafes.length})',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: (adminService.metrics?.pendingApprovals ?? 0) > 0,
                label: Text('${adminService.metrics?.pendingApprovals ?? 0}'),
                child: const Icon(Icons.approval, size: 18),
              ),
              text: 'Approvals (${adminService.metrics?.pendingApprovals ?? 0})',
            ),
            Tab(
              icon: const Icon(Icons.shield_outlined, size: 18),
              text: 'Admin Access (${adminService.adminUsers.length})',
            ),
          ],
        ),
      ),
      body: adminService.isLoading && adminService.allCafes.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF7A00)),
                  SizedBox(height: 16),
                  Text('Loading platform metrics & cafes...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                // Top Metrics KPI Strip
                _buildMetricsStrip(context, adminService.metrics),
                // Tabs Body
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Cafes & Subscriptions
                      _buildCafesTab(context, adminService),
                      // Tab 2: Pending Approvals
                      _buildApprovalsTab(context, adminService),
                      // Tab 3: Admin Access Control
                      _buildAdminsTab(context, adminService),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // --------------------------------------------------------------------------
  // TOP METRICS KPI STRIP
  // --------------------------------------------------------------------------
  Widget _buildMetricsStrip(BuildContext context, PlatformMetrics? metrics) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14141B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF22222E) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              _buildKpiCard(
                title: 'Total Cafes',
                value: '${metrics?.totalCafes ?? 0}',
                icon: Icons.storefront_rounded,
                color: const Color(0xFF2563EB),
                isWide: isWide,
              ),
              _buildKpiCard(
                title: 'Total Platform GMV',
                value: '₹${NumberFormat('#,##,##0').format(metrics?.totalRevenue ?? 0)}',
                icon: Icons.currency_rupee,
                color: const Color(0xFF16A34A),
                isWide: isWide,
              ),
              _buildKpiCard(
                title: 'Total Orders',
                value: '${metrics?.totalOrders ?? 0}',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF9333EA),
                isWide: isWide,
              ),
              _buildKpiCard(
                title: 'Pending Approvals',
                value: '${metrics?.pendingApprovals ?? 0}',
                icon: Icons.pending_actions_rounded,
                color: (metrics?.pendingApprovals ?? 0) > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                isWide: isWide,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isWide,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color.withOpacity(0.9),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 1: CAFES & PLAN MONITOR
  // --------------------------------------------------------------------------
  Widget _buildCafesTab(BuildContext context, SuperAdminService adminService) {
    final filtered = adminService.filteredCafes;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      color: const Color(0xFFFF7A00),
      onRefresh: () => adminService.refreshAll(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Bar & Filter Pills
            Card(
              elevation: 0,
              color: isDark ? const Color(0xFF1A1A24) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isDark ? const Color(0xFF2A2A38) : const Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by cafe name, owner email, or plan...',
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  adminService.setSearchQuery('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onChanged: (val) => adminService.setSearchQuery(val),
                    ),
                    const SizedBox(height: 10),
                    // Quick Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(adminService, 'ALL', 'All (${adminService.allCafes.length})'),
                          _buildFilterChip(
                            adminService,
                            'TRIAL',
                            'Trials (${adminService.allCafes.where((c) => c.isTrial && !c.isSuspended).length})',
                          ),
                          _buildFilterChip(
                            adminService,
                            'ACTIVE',
                            'Paid Plans (${adminService.allCafes.where((c) => !c.isTrial && !c.isExpired && !c.isSuspended).length})',
                          ),
                          _buildFilterChip(
                            adminService,
                            'EXPIRING_SOON',
                            'Expiring <=3d (${adminService.allCafes.where((c) => c.isExpiringSoon && !c.isSuspended).length})',
                          ),
                          _buildFilterChip(
                            adminService,
                            'EXPIRED',
                            'Expired (${adminService.allCafes.where((c) => c.isExpired && !c.isSuspended).length})',
                          ),
                          _buildFilterChip(
                            adminService,
                            'SUSPENDED',
                            'Suspended (${adminService.allCafes.where((c) => c.isSuspended).length})',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (filtered.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No cafes found matching your filter criteria.',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) => _buildCafeCard(ctx, filtered[i], adminService),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(SuperAdminService adminService, String code, String label) {
    final isSelected = adminService.statusFilter == code;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        selectedColor: const Color(0xFFFF7A00).withOpacity(0.2),
        checkmarkColor: const Color(0xFFFF7A00),
        onSelected: (_) => adminService.setStatusFilter(code),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // CAFE CARD WITH PLAN MONITOR & ACCESS CONTROLS
  // --------------------------------------------------------------------------
  Widget _buildCafeCard(BuildContext context, CafeOverviewAdmin cafe, SuperAdminService adminService) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = cafe.daysRemaining;

    Color daysColor = const Color(0xFF16A34A); // Green
    String daysText = '🟢 $days Days Left';
    if (cafe.isExpired) {
      daysColor = const Color(0xFFDC2626); // Red
      daysText = '🔴 Expired';
    } else if (days <= 3) {
      daysColor = const Color(0xFFD97706); // Amber
      daysText = '⚠️ $days Days Left (Expiring Soon)';
    }

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1A1A24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: cafe.isSuspended
              ? Colors.red.withOpacity(0.5)
              : (isDark ? const Color(0xFF2E2E3E) : const Color(0xFFE2E8F0)),
          width: cafe.isSuspended ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Cafe Name & Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cafe.isSuspended
                        ? Colors.red.withOpacity(0.15)
                        : const Color(0xFFFF7A00).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    cafe.isSuspended ? Icons.block : Icons.store,
                    color: cafe.isSuspended ? Colors.red : const Color(0xFFFF7A00),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cafe.cafeName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          // Suspension / Active Status Pill
                          if (cafe.isSuspended)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.red.withOpacity(0.4)),
                              ),
                              child: const Text(
                                'SUSPENDED',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.3)),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Color(0xFF16A34A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            cafe.ownerEmail,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if (cafe.createdAt != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              '• Joined ${DateFormat('dd MMM yyyy').format(cafe.createdAt!)}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Plan & Validity Ribbon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222230) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? const Color(0xFF2D2D40) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  // Plan Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Subscription',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              cafe.formattedTierDisplay,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Validity / Countdown
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: daysColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: daysColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          daysText,
                          style: TextStyle(
                            color: daysColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (cafe.endDate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Renews/Ends: ${DateFormat('dd MMM yyyy').format(cafe.endDate!)}',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Quotas & Stats Row
            Row(
              children: [
                _buildStatPill(
                  icon: Icons.table_bar,
                  label: 'Tables: ${cafe.tablesCount}/${cafe.maxTables}',
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildStatPill(
                  icon: Icons.fastfood_outlined,
                  label: 'Items: ${cafe.itemsCount}/${cafe.maxItems}',
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildStatPill(
                  icon: Icons.receipt_long,
                  label: '${cafe.ordersCount} Orders · ₹${NumberFormat('#,##0').format(cafe.totalRevenue)}',
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Buttons: Grant/Extend Plan, Suspend/Restore Access
            Row(
              children: [
                // Manage Plan Button
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A00),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text(
                      'Extend / Change Plan',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _showPlanGrantDialog(context, cafe, adminService),
                  ),
                ),
                const SizedBox(width: 8),
                // Suspend / Restore Toggle
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cafe.isSuspended ? Colors.green : Colors.red,
                    side: BorderSide(color: cafe.isSuspended ? Colors.green : Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  icon: Icon(cafe.isSuspended ? Icons.lock_open : Icons.block, size: 16),
                  label: Text(
                    cafe.isSuspended ? 'Restore Access' : 'Suspend Access',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _toggleAccess(context, cafe, adminService),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill({required IconData icon, required String label, required bool isDark}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E28) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // DIALOG: GRANT / EXTEND SUBSCRIPTION PLAN
  // --------------------------------------------------------------------------
  void _showPlanGrantDialog(BuildContext context, CafeOverviewAdmin cafe, SuperAdminService adminService) {
    String selectedTier = cafe.tier == 'TRIAL' ? 'STARTER' : cafe.tier;
    int selectedDays = 30;
    final noteController = TextEditingController(text: 'Extended by Super Admin');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.bolt, color: Color(0xFFFF7A00)),
                const SizedBox(width: 8),
                Expanded(child: Text('Extend / Change Plan for ${cafe.cafeName}')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Subscription Tier:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedTier,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'STARTER', child: Text('Starter Plan (5 Tables, 30 Items - ₹399)')),
                      DropdownMenuItem(value: 'GROWTH', child: Text('Growth Plan (15 Tables, 70 Items - ₹799)')),
                      DropdownMenuItem(value: 'ENTERPRISE', child: Text('Enterprise (Unlimited Tables & Menu - ₹1,499)')),
                      DropdownMenuItem(value: 'TRIAL', child: Text('Free Trial (Full Features)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => selectedTier = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Duration / Validity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [7, 14, 30, 90, 365].map((d) {
                      final isSel = selectedDays == d;
                      String label = '+$d Days';
                      if (d == 30) label = '1 Month (30d)';
                      if (d == 90) label = '3 Months (90d)';
                      if (d == 365) label = '1 Year (365d)';
                      return ChoiceChip(
                        selected: isSel,
                        label: Text(label),
                        selectedColor: const Color(0xFFFF7A00).withOpacity(0.25),
                        onSelected: (_) => setDlgState(() => selectedDays = d),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Admin Note / Reason:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. UPI payment received / Special privilege',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
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
                onPressed: () async {
                  Navigator.pop(ctx);
                  final res = await adminService.grantSubscription(
                    cafeId: cafe.cafeId,
                    tier: selectedTier,
                    days: selectedDays,
                    notes: noteController.text.trim(),
                  );

                  if (context.mounted) {
                    if (res['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.green.shade800,
                          content: Text('✅ ${res['message'] ?? 'Subscription activated successfully!'}'),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.red,
                          content: Text('Error: ${res['error'] ?? 'Failed to update plan'}'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Apply Plan & Grant Access'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ACTION: SUSPEND OR RESTORE CAFE ACCESS
  // --------------------------------------------------------------------------
  void _toggleAccess(BuildContext context, CafeOverviewAdmin cafe, SuperAdminService adminService) {
    if (cafe.isSuspended) {
      // Restore access
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore Cafe Access?'),
          content: Text('Are you sure you want to restore ordering and dashboard access for "${cafe.cafeName}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await adminService.toggleCafeAccess(cafeId: cafe.cafeId, isSuspended: false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: res['success'] == true ? Colors.green.shade800 : Colors.red,
                      content: Text(res['success'] == true ? '✅ Access restored for "${cafe.cafeName}"!' : 'Error: ${res['error']}'),
                    ),
                  );
                }
              },
              child: const Text('Restore Access'),
            ),
          ],
        ),
      );
    } else {
      // Suspend access
      final reasonController = TextEditingController(text: 'Subscription expired / Policy review');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Suspend Cafe Access'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Suspending "${cafe.cafeName}" will immediately block new customer orders and lock table ordering until reactivated.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text('Reason for suspension:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Non-payment, fraud check, expired plan',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await adminService.toggleCafeAccess(
                  cafeId: cafe.cafeId,
                  isSuspended: true,
                  reason: reasonController.text.trim(),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: res['success'] == true ? Colors.red.shade800 : Colors.red,
                      content: Text(res['success'] == true ? '🔒 "${cafe.cafeName}" has been suspended.' : 'Error: ${res['error']}'),
                    ),
                  );
                }
              },
              child: const Text('Suspend Cafe'),
            ),
          ],
        ),
      );
    }
  }

  // --------------------------------------------------------------------------
  // TAB 2: PENDING APPROVALS
  // --------------------------------------------------------------------------
  Widget _buildApprovalsTab(BuildContext context, SuperAdminService adminService) {
    final list = adminService.pendingApprovals;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade400),
              const SizedBox(height: 16),
              const Text(
                'All Caught Up!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'There are no pending subscription payment approvals at this time.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final item = list[i];
        final subId = item['subscription_id'] as String;
        final cafeName = item['cafe_name'] as String? ?? 'Cafe';
        final tier = item['tier'] as String? ?? 'STARTER';
        final amount = item['amount_paid']?.toString() ?? '399';
        final utr = item['utr_number'] as String? ?? 'N/A';
        final created = item['created_at'] != null ? DateTime.tryParse(item['created_at'].toString()) : null;

        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF1A1A24) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? const Color(0xFF2E2E3E) : const Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFEDE7F6),
                      child: Icon(Icons.payment, color: Color(0xFF5F259F)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cafeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text('Plan: $tier · Amount: ₹$amount', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('PENDING', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Text('UTR Number: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(utr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 14),
                      tooltip: 'Copy UTR',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: utr));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('UTR copied to clipboard!'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                    if (created != null) ...[
                      const Spacer(),
                      Text(DateFormat('dd MMM hh:mm a').format(created), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve & Activate (30d)'),
                        onPressed: () async {
                          final res = await adminService.approveSubscription(subId);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: res['success'] == true ? Colors.green.shade800 : Colors.red,
                                content: Text(res['message'] ?? res['error'] ?? 'Result'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () async {
                        final res = await adminService.rejectSubscription(subId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(res['message'] ?? res['error'] ?? 'Rejected')),
                          );
                        }
                      },
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // TAB 3: ADMIN ACCESS MANAGEMENT
  // --------------------------------------------------------------------------
  Widget _buildAdminsTab(BuildContext context, SuperAdminService adminService) {
    final admins = adminService.adminUsers;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Platform Super Admins', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      'Users listed here have full administrative authority over all cafes and platform subscriptions.',
                      style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7A00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Add Admin'),
                onPressed: () => _showAddAdminDialog(context, adminService),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Card(
            elevation: 0,
            color: isDark ? const Color(0xFF1A1A24) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isDark ? const Color(0xFF2E2E3E) : const Color(0xFFE2E8F0)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: admins.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final admin = admins[i];
                final isRootAdmin = admin.email.toLowerCase() == 'ershobhit17@gmail.com';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isRootAdmin ? const Color(0xFFFFF3E0) : const Color(0xFFE3F2FD),
                    child: Icon(
                      isRootAdmin ? Icons.star : Icons.security,
                      color: isRootAdmin ? const Color(0xFFFF7A00) : const Color(0xFF1976D2),
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(admin.email, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      if (isRootAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF7A00).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ROOT OWNER',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF7A00),
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    'Role: ${admin.role.toUpperCase()} ${admin.createdAt != null ? "• Added ${DateFormat('dd MMM yyyy').format(admin.createdAt!)}" : ""}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: isRootAdmin
                      ? const Chip(
                          label: Text('Protected', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          backgroundColor: Colors.transparent,
                        )
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          tooltip: 'Revoke Admin Access',
                          onPressed: () => _confirmRemoveAdmin(context, admin.email, adminService),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddAdminDialog(BuildContext context, SuperAdminService adminService) {
    final emailController = TextEditingController();
    String role = 'admin';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Platform Admin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the email of the person you want to grant admin access:'),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'user@example.com',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(
                  labelText: 'Admin Role',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin (Can inspect & approve)')),
                  DropdownMenuItem(value: 'super_admin', child: Text('Super Admin (Full privileges)')),
                ],
                onChanged: (val) {
                  if (val != null) setDlgState(() => role = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A00),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid email address')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                final res = await adminService.addAdmin(email, role: role);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: res['success'] == true ? Colors.green.shade800 : Colors.red,
                      content: Text(res['message'] ?? res['error'] ?? 'Admin status updated'),
                    ),
                  );
                }
              },
              child: const Text('Grant Access'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveAdmin(BuildContext context, String email, SuperAdminService adminService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Admin Access?'),
        content: Text('Are you sure you want to revoke admin privileges for $email? They will no longer be able to access the admin panel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await adminService.removeAdmin(email);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true ? Colors.green.shade800 : Colors.red,
                    content: Text(res['message'] ?? res['error'] ?? 'Admin access revoked'),
                  ),
                );
              }
            },
            child: const Text('Revoke Access'),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of the Admin Console?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthService>().signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
