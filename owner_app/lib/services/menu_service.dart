import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/menu_item.dart';

class MenuService extends ChangeNotifier {
  List<MenuItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<MenuItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<String> get categories {
    final cats = _items.map((i) => i.category).toSet().toList();
    cats.sort();
    return cats;
  }

  // Demo fallback items
  final List<MenuItem> _demoItems = [
    MenuItem(id: 'd-1', cafeId: SupabaseConfig.demoCafeId, name: 'Caramel Macchiato', category: 'Hot Beverages', price: 240, offerPrice: 199, description: 'Rich espresso with steamed milk & vanilla-caramel.', imageUrl: 'https://images.unsplash.com/photo-1485808191679-5f86510681a2?w=300', isAvailable: true),
    MenuItem(id: 'd-2', cafeId: SupabaseConfig.demoCafeId, name: 'Hazelnut Cappuccino', category: 'Hot Beverages', price: 220, description: 'Double shot espresso topped with micro-foam and hazelnut.', imageUrl: 'https://images.unsplash.com/photo-1572442388796-11668a67e53d?w=300', isAvailable: true),
    MenuItem(id: 'd-3', cafeId: SupabaseConfig.demoCafeId, name: 'Sweet Cream Cold Brew', category: 'Cold Brews', price: 280, offerPrice: 249, description: 'Steeped for 18 hours with sweet cream float.', imageUrl: 'https://images.unsplash.com/photo-1517701550927-30cf4ba1dba5?w=300', isAvailable: true),
    MenuItem(id: 'd-4', cafeId: SupabaseConfig.demoCafeId, name: 'Classic Mango Frappe', category: 'Cold Brews', price: 250, description: 'Blended chilled milk and fresh Alphonso mangoes.', imageUrl: 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=300', isAvailable: false),
    MenuItem(id: 'd-5', cafeId: SupabaseConfig.demoCafeId, name: 'Pesto Grilled Sourdough', category: 'Artisanal Bites', price: 320, offerPrice: 280, description: 'Aged cheddar & pesto on toasted sourdough.', imageUrl: 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=300', isAvailable: true),
    MenuItem(id: 'd-6', cafeId: SupabaseConfig.demoCafeId, name: 'Crispy Truffle Fries', category: 'Artisanal Bites', price: 230, offerPrice: 199, description: 'Golden skin-on fries with truffle oil and parmesan.', imageUrl: 'https://images.unsplash.com/photo-1576107232684-1279f3908594?w=300', isAvailable: true),
    MenuItem(id: 'd-7', cafeId: SupabaseConfig.demoCafeId, name: 'Wild Mushroom Alfredo', category: 'Main Course', price: 390, description: 'Sautéed mushrooms in garlic-parmesan sauce.', imageUrl: 'https://images.unsplash.com/photo-1621996346565-e3d5d62817d2?w=300', isAvailable: true),
    MenuItem(id: 'd-8', cafeId: SupabaseConfig.demoCafeId, name: 'Artisan Margherita Pizza', category: 'Main Course', price: 440, offerPrice: 399, description: 'San Marzano tomato base & buffalo mozzarella.', imageUrl: 'https://images.unsplash.com/photo-1604382355076-af4b0eb60143?w=300', isAvailable: true),
    MenuItem(id: 'd-9', cafeId: SupabaseConfig.demoCafeId, name: 'New York Cheesecake', category: 'Desserts', price: 270, offerPrice: 239, description: 'Silky baked cheesecake with blueberry compote.', imageUrl: 'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?w=300', isAvailable: true),
    MenuItem(id: 'd-10', cafeId: SupabaseConfig.demoCafeId, name: 'Fudge Brownie Sundae', category: 'Desserts', price: 260, description: 'Warm dark fudge brownie with vanilla gelato.', imageUrl: 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=300', isAvailable: true),
  ];

  Future<void> fetchMenu(String cafeId, {bool isDemo = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 300));
      _items = List.from(_demoItems);
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('menu_items')
          .select('*')
          .eq('cafe_id', cafeId)
          .order('category')
          .order('name');

      _items = (data as List).map((json) => MenuItem.fromJson(json)).toList();
    } catch (e) {
      _errorMessage = 'Failed to load menu: $e';
      _items = List.from(_demoItems);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> toggleAvailability(MenuItem item, {bool isDemo = false}) async {
    final nextState = !item.isAvailable;
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _items[index] = item.copyWith(isAvailable: nextState);
      notifyListeners();
    }

    if (isDemo || !SupabaseConfig.isConfigured) {
      return true;
    }

    try {
      await Supabase.instance.client
          .from('menu_items')
          .update({'is_available': nextState})
          .eq('id', item.id);
      return true;
    } catch (e) {
      // Revert on error
      if (index != -1) {
        _items[index] = item;
        notifyListeners();
      }
      _errorMessage = 'Failed to update stock status: $e';
      return false;
    }
  }

  Future<bool> saveItem({
    String? id,
    required String cafeId,
    required String name,
    String? description,
    required String category,
    required double price,
    double? offerPrice,
    String? imageUrl,
    bool isAvailable = true,
    bool isDemo = false,
  }) async {
    if (isDemo || !SupabaseConfig.isConfigured) {
      if (id == null || id.isEmpty) {
        final newItem = MenuItem(
          id: 'demo-item-${DateTime.now().millisecondsSinceEpoch}',
          cafeId: cafeId,
          name: name,
          description: description,
          category: category,
          price: price,
          offerPrice: offerPrice,
          imageUrl: imageUrl,
          isAvailable: isAvailable,
        );
        _items.add(newItem);
      } else {
        final index = _items.indexWhere((i) => i.id == id);
        if (index != -1) {
          _items[index] = MenuItem(
            id: id,
            cafeId: cafeId,
            name: name,
            description: description,
            category: category,
            price: price,
            offerPrice: offerPrice,
            imageUrl: imageUrl,
            isAvailable: isAvailable,
          );
        }
      }
      notifyListeners();
      return true;
    }

    try {
      final payload = {
        'cafe_id': cafeId,
        'name': name,
        'description': description,
        'category': category,
        'price': price,
        'offer_price': offerPrice,
        'image_url': imageUrl,
        'is_available': isAvailable,
      };

      if (id == null || id.isEmpty) {
        final res = await Supabase.instance.client.from('menu_items').insert(payload).select().single();
        _items.add(MenuItem.fromJson(res));
      } else {
        final res = await Supabase.instance.client.from('menu_items').update(payload).eq('id', id).select().single();
        final updated = MenuItem.fromJson(res);
        final index = _items.indexWhere((i) => i.id == id);
        if (index != -1) _items[index] = updated;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to save menu item: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteItem(String itemId, {bool isDemo = false}) async {
    if (isDemo || !SupabaseConfig.isConfigured) {
      _items.removeWhere((i) => i.id == itemId);
      notifyListeners();
      return true;
    }

    try {
      await Supabase.instance.client.from('menu_items').delete().eq('id', itemId);
      _items.removeWhere((i) => i.id == itemId);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete item: $e';
      notifyListeners();
      return false;
    }
  }
}
