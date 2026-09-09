import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/table_model.dart';

class CafeService extends ChangeNotifier {
  List<CafeTable> _tables = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<CafeTable> get tables => _tables;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Demo Fallback Tables
  final List<CafeTable> _demoTables = [
    CafeTable(id: 't-1', cafeId: SupabaseConfig.demoCafeId, tableNumber: 1, qrToken: '11111111-1111-1111-1111-111111111101'),
    CafeTable(id: 't-2', cafeId: SupabaseConfig.demoCafeId, tableNumber: 2, qrToken: '11111111-1111-1111-1111-111111111102'),
    CafeTable(id: 't-3', cafeId: SupabaseConfig.demoCafeId, tableNumber: 3, qrToken: '11111111-1111-1111-1111-111111111103'),
    CafeTable(id: 't-4', cafeId: SupabaseConfig.demoCafeId, tableNumber: 4, qrToken: '11111111-1111-1111-1111-111111111104'),
    CafeTable(id: 't-5', cafeId: SupabaseConfig.demoCafeId, tableNumber: 5, qrToken: '11111111-1111-1111-1111-111111111105'),
  ];

  Future<void> fetchTables(String cafeId, {bool isDemo = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (isDemo || !SupabaseConfig.isConfigured) {
      await Future.delayed(const Duration(milliseconds: 300));
      _tables = List.from(_demoTables);
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('tables')
          .select('*')
          .eq('cafe_id', cafeId)
          .order('table_number');

      _tables = (data as List).map((json) => CafeTable.fromJson(json)).toList();
    } catch (e) {
      _errorMessage = 'Failed to load tables: $e';
      _tables = List.from(_demoTables);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addTable(String cafeId, int tableNumber, {bool isDemo = false}) async {
    if (isDemo || !SupabaseConfig.isConfigured) {
      final newTable = CafeTable(
        id: 't-${DateTime.now().millisecondsSinceEpoch}',
        cafeId: cafeId,
        tableNumber: tableNumber,
        qrToken: 'demo-qr-${DateTime.now().millisecondsSinceEpoch}',
      );
      _demoTables.add(newTable);
      _tables = List.from(_demoTables);
      notifyListeners();
      return true;
    }

    try {
      final res = await Supabase.instance.client.from('tables').insert({
        'cafe_id': cafeId,
        'table_number': tableNumber,
      }).select().single();

      final created = CafeTable.fromJson(res);
      _tables.add(created);
      _tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add table: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteTable(String tableId, {bool isDemo = false}) async {
    if (isDemo || !SupabaseConfig.isConfigured) {
      _demoTables.removeWhere((t) => t.id == tableId);
      _tables.removeWhere((t) => t.id == tableId);
      notifyListeners();
      return true;
    }

    try {
      await Supabase.instance.client.from('tables').delete().eq('id', tableId);
      _tables.removeWhere((t) => t.id == tableId);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete table: $e';
      notifyListeners();
      return false;
    }
  }
}
