import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/menu_item.dart';
import '../../services/auth_service.dart';
import '../../services/menu_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/cafe_food_image.dart';
import '../subscription/subscription_plans_screen.dart';
import 'edit_menu_item_dialog.dart';

class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  String _selectedCategory = 'ALL';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMenu();
    });
  }

  void _loadMenu() {
    final auth = context.read<AuthService>();
    context.read<MenuService>().fetchMenu(auth.currentCafeId, isDemo: auth.isDemoMode);
  }

  void _showUpgradePlanDialog(BuildContext context, int currentLimit) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.upgrade, color: Color(0xFFFF7A00)),
            SizedBox(width: 8),
            Text('Plan Limit Reached'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have reached the maximum limit of $currentLimit menu items allowed on your current plan.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Upgrade to Growth (70 Items) or Enterprise (Unlimited) to expand your food and beverage catalog.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7A00),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.flash_on, size: 16),
            label: const Text('Upgrade Plan'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionPlansScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openAddDialog(BuildContext context, MenuService menuService, AuthService auth) {
    final subService = context.read<SubscriptionService>();
    if (subService.overview != null && subService.overview!.isItemsLimitReached) {
      _showUpgradePlanDialog(context, subService.overview!.maxItems);
      return;
    }

    showDialog(
      context: context,
      builder: (_) => EditMenuItemDialog(
        cafeId: auth.currentCafeId,
        existingCategories: menuService.categories,
        onSave: ({
          id,
          required cafeId,
          required name,
          description,
          required category,
          required price,
          offerPrice,
          imageUrl,
          isAvailable = true,
        }) async {
          final ok = await menuService.saveItem(
            id: id,
            cafeId: cafeId,
            name: name,
            description: description,
            category: category,
            price: price,
            offerPrice: offerPrice,
            imageUrl: imageUrl,
            isAvailable: isAvailable,
            isDemo: auth.isDemoMode,
          );
          if (!ok && menuService.errorMessage != null && menuService.errorMessage!.contains('LIMIT_EXCEEDED')) {
            if (context.mounted) {
              _showUpgradePlanDialog(context, subService.overview?.maxItems ?? 30);
            }
          }
          return ok;
        },
      ),
    );
  }

  void _openEditDialog(BuildContext context, MenuItem item, MenuService menuService, AuthService auth) {
    showDialog(
      context: context,
      builder: (_) => EditMenuItemDialog(
        item: item,
        cafeId: auth.currentCafeId,
        existingCategories: menuService.categories,
        onSave: ({
          id,
          required cafeId,
          required name,
          description,
          required category,
          required price,
          offerPrice,
          imageUrl,
          isAvailable = true,
        }) {
          return menuService.saveItem(
            id: id,
            cafeId: cafeId,
            name: name,
            description: description,
            category: category,
            price: price,
            offerPrice: offerPrice,
            imageUrl: imageUrl,
            isAvailable: isAvailable,
            isDemo: auth.isDemoMode,
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, MenuItem item, MenuService menuService, AuthService auth) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete this menu item?'),
        content: Text('Are you sure you want to delete "${item.name}"? This will safely remove it from the active menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await menuService.deleteItem(item.id, isDemo: auth.isDemoMode);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Menu item deleted successfully.'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(menuService.errorMessage ?? 'Failed to delete menu item.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final menuService = context.watch<MenuService>();

    final categories = ['ALL', ...menuService.categories];
    final filteredItems = menuService.items.where((item) {
      final matchesCat = _selectedCategory == 'ALL' || item.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (item.description != null && item.description!.toLowerCase().contains(_searchQuery.toLowerCase()));
      return matchesCat && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              auth.currentCafeName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Text('Menu Management', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMenu),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFFF7A00),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Menu Item', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openAddDialog(context, menuService, auth),
      ),
      body: Column(
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // Category Chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat == 'ALL' ? 'All Items' : cat),
                  selected: isSelected,
                  selectedColor: const Color(0xFFFF7A00),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Items List
          Expanded(
            child: menuService.isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7A00)))
                : filteredItems.isEmpty
                    ? Center(
                        child: Text(
                          'No menu items found',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Image
                                  CafeFoodImage(
                                    imageUrl: item.imageUrl,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  const SizedBox(width: 12),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        Text(
                                          item.category,
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              '₹${item.effectivePrice.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                color: Color(0xFFFF7A00),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (item.hasOffer) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '₹${item.price.toStringAsFixed(0)}',
                                                style: const TextStyle(
                                                  decoration: TextDecoration.lineThrough,
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${item.discountPercentage}% OFF',
                                                  style: TextStyle(color: Colors.green.shade700, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Stock Switch & Action Buttons
                                  Column(
                                    children: [
                                      Switch(
                                        value: item.isAvailable,
                                        activeThumbColor: const Color(0xFFFF7A00),
                                        onChanged: (val) {
                                          menuService.toggleAvailability(item, isDemo: auth.isDemoMode);
                                        },
                                      ),
                                      Text(
                                        item.isAvailable ? 'In Stock' : 'Out of Stock',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: item.isAvailable ? Colors.green.shade700 : Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ),

                                  PopupMenuButton<String>(
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        _openEditDialog(context, item, menuService, auth);
                                      } else if (action == 'delete') {
                                        _confirmDelete(context, item, menuService, auth);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Edit Item')),
                                      const PopupMenuItem(value: 'delete', child: Text('Delete Item', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
