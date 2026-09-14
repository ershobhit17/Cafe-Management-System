import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/earnings_service.dart';
import '../../services/order_service.dart';
import '../../services/sound_service.dart';
import '../auth/login_screen.dart';
import '../dashboard/live_orders_screen.dart';
import '../earnings/earnings_screen.dart';
import '../kitchen/kitchen_display_screen.dart';
import '../menu/menu_management_screen.dart';
import '../subscription/subscription_plans_screen.dart';
import '../tables/tables_qr_screen.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    LiveOrdersScreen(),
    MenuManagementScreen(),
    TablesQrScreen(),
    EarningsScreen(),
  ];

  void _showSettingsDialog(BuildContext context) {
    final auth = context.read<AuthService>();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cafe Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7A00).withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const CircleAvatar(
                      backgroundColor: Color(0xFFFFF3E0),
                      child: Icon(Icons.storefront, color: Color(0xFFFF7A00)),
                    ),
                  ),
                ),
                title: Text(
                  auth.currentCafeName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text(auth.currentUser?.email ?? (auth.isDemoMode ? 'Demo Mode' : 'Cafe Owner Account')),
              ),
              const Divider(),
              if (auth.isSuperAdmin) ...[
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A00).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF7A00).withOpacity(0.3)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFF7A00),
                      child: Icon(Icons.admin_panel_settings, color: Colors.white),
                    ),
                    title: const Text(
                      'Super Admin Console',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF7A00)),
                    ),
                    subtitle: const Text(
                      'Systematic access to all cafes, plans & approvals',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFFF7A00)),
                    onTap: () {
                      Navigator.pop(context);
                      auth.setSuperAdminViewMode(true);
                    },
                  ),
                ),
                const Divider(),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(Icons.rocket_launch, color: Color(0xFFFF7A00)),
                ),
                title: const Text('Upgrade & Expand Plan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Expand table capacity, menu & premium growth features', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscriptionPlansScreen()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(Icons.soup_kitchen, color: Color(0xFFFF7A00)),
                ),
                title: const Text('Kitchen Display (KDS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Live order tickets & thermal KOT print station', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const KitchenDisplayScreen()),
                  );
                },
              ),
              const Divider(),
            Consumer<SoundService>(
              builder: (context, sound, _) => Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      sound.isSoundEnabled ? Icons.notifications_active : Icons.notifications_off,
                      color: const Color(0xFFFF7A00),
                    ),
                    title: const Text('Order Bell Ring', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Ring melodic bell when new order arrives', style: TextStyle(fontSize: 12)),
                    value: sound.isSoundEnabled,
                    activeThumbColor: const Color(0xFFFF7A00),
                    onChanged: (val) => sound.setSoundEnabled(val),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.volume_up, size: 16, color: Color(0xFFFF7A00)),
                      label: const Text('Test Bell Ring', style: TextStyle(fontSize: 12, color: Color(0xFFFF7A00), fontWeight: FontWeight.bold)),
                      onPressed: () => sound.testSound(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Sign Out'),
            onPressed: () async {
              Navigator.pop(context);
              await auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isSuperAdmin = auth.isSuperAdmin;
    final orderService = context.watch<OrderService>();
    final activeOrdersCount = orderService.liveOrders.length;

    return Scaffold(
      body: Column(
        children: [
          if (isSuperAdmin)
            Container(
              color: const Color(0xFF1E293B),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings, color: Color(0xFFFF7A00), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Viewing as Cafe Owner (Super Admin Mode)',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    InkWell(
                      onTap: () => auth.setSuperAdminViewMode(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF7A00),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Admin Console',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        indicatorColor: const Color(0xFFFF7A00).withValues(alpha: 0.2),
        onDestinationSelected: (idx) {
          if (idx == 4) {
            _showSettingsDialog(context);
          } else {
            setState(() => _currentIndex = idx);
            if (idx == 3) {
              final auth = context.read<AuthService>();
              context.read<EarningsService>().fetchEarnings(auth.currentCafeId, isDemo: auth.isDemoMode);
            }
          }
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeOrdersCount > 0,
              label: Text('$activeOrdersCount'),
              backgroundColor: const Color(0xFFFF7A00),
              child: const Icon(Icons.receipt_long_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: activeOrdersCount > 0,
              label: Text('$activeOrdersCount'),
              backgroundColor: const Color(0xFFFF7A00),
              child: const Icon(Icons.receipt_long, color: Color(0xFFFF7A00)),
            ),
            label: 'Orders',
          ),
          const NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu, color: Color(0xFFFF7A00)),
            label: 'Menu',
          ),
          const NavigationDestination(
            icon: Icon(Icons.qr_code_2_outlined),
            selectedIcon: Icon(Icons.qr_code_2, color: Color(0xFFFF7A00)),
            label: 'Tables & QR',
          ),
          const NavigationDestination(
            icon: Icon(Icons.trending_up_outlined),
            selectedIcon: Icon(Icons.trending_up, color: Color(0xFFFF7A00)),
            label: 'Earnings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFFFF7A00)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
