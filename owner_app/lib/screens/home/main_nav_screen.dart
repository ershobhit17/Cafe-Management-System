import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/order_service.dart';
import '../auth/login_screen.dart';
import '../dashboard/live_orders_screen.dart';
import '../earnings/earnings_screen.dart';
import '../menu/menu_management_screen.dart';
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront, color: Color(0xFFFF7A00)),
              title: const Text('Aroma Artisan Cafe'),
              subtitle: Text('Cafe ID: ${auth.currentCafeId.substring(0, 8)}...'),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.security, color: Colors.blue),
              title: const Text('Session Security'),
              subtitle: Text(auth.isDemoMode ? 'Demo Mode Active' : 'Persistent Supabase Token'),
            ),
          ],
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
    final orderService = context.watch<OrderService>();
    final activeOrdersCount = orderService.liveOrders.length;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        indicatorColor: const Color(0xFFFF7A00).withOpacity(0.2),
        onDestinationSelected: (idx) {
          if (idx == 4) {
            _showSettingsDialog(context);
          } else {
            setState(() => _currentIndex = idx);
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
