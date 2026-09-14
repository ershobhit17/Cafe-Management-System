import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class AuthService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  static const String _keyToken = 'owner_supabase_refresh_token';
  static const String _keyDemoAuth = 'owner_demo_auth_active';

  bool _isLoading = false;
  bool _isAuthenticated = false;
  bool _isDemoMode = false;
  String? _errorMessage;
  User? _currentUser;
  String? _cafeId;
  String _cafeName = 'Loading cafe...';
  bool _isCafeProfileLoaded = false;
  bool _isSuperAdmin = false;
  bool _superAdminViewMode = true;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isDemoMode => _isDemoMode;
  bool get isCafeProfileLoaded => _isCafeProfileLoaded;
  bool get isSuperAdmin => _isSuperAdmin;
  bool get isSuperAdminViewActive => _isSuperAdmin && _superAdminViewMode;
  String? get errorMessage => _errorMessage;
  User? get currentUser => _currentUser;
  String get currentCafeId => _cafeId ?? SupabaseConfig.demoCafeId;
  String get currentCafeName => _cafeName;
  String get cafeName => _cafeName;

  void toggleSuperAdminViewMode() {
    _superAdminViewMode = !_superAdminViewMode;
    notifyListeners();
  }

  void setSuperAdminViewMode(bool active) {
    _superAdminViewMode = active;
    notifyListeners();
  }

  Future<void> _safeStorageWrite(String key, String? value) async {
    if (value == null) return;
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('Storage write warning (non-fatal): $e');
    }
  }

  Future<String?> _safeStorageRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('Storage read warning (non-fatal): $e');
      return null;
    }
  }

  Future<void> _safeStorageDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('Storage delete warning (non-fatal): $e');
    }
  }

  Future<void> initializeAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (SupabaseConfig.isConfigured) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          _currentUser = Supabase.instance.client.auth.currentUser;
          _isAuthenticated = true;
          _isDemoMode = false;
          await _resolveCafeId();
          await _checkSuperAdminStatus();
        } else {
          // Check secure storage for saved refresh token
          final savedToken = await _safeStorageRead(_keyToken);
          if (savedToken != null && savedToken.isNotEmpty) {
            try {
              final res = await Supabase.instance.client.auth.setSession(savedToken);
              if (res.session != null) {
                _currentUser = res.user;
                _isAuthenticated = true;
                _isDemoMode = false;
                await _resolveCafeId();
                await _checkSuperAdminStatus();
              }
            } catch (e) {
              debugPrint('Saved token expired or invalid: $e');
            }
          }
        }
      } else {
        // Check if demo mode was active previously
        final savedDemo = await _safeStorageRead(_keyDemoAuth);
        if (savedDemo == 'true') {
          _isAuthenticated = true;
          _isDemoMode = true;
          _cafeId = SupabaseConfig.demoCafeId;
        }
      }
    } catch (e) {
      debugPrint('Auth restoration error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _checkSuperAdminStatus() async {
    final email = _currentUser?.email?.trim().toLowerCase();
    if (email == 'ershobhit17@gmail.com') {
      _isSuperAdmin = true;
      _superAdminViewMode = true;
      return;
    }

    if (SupabaseConfig.isConfigured && _currentUser != null) {
      try {
        final res = await Supabase.instance.client.rpc('is_super_admin');
        _isSuperAdmin = (res == true);
        if (_isSuperAdmin) {
          _superAdminViewMode = true;
        }
      } catch (e) {
        debugPrint('Error checking super admin status: $e');
        _isSuperAdmin = (email == 'ershobhit17@gmail.com');
      }
    } else {
      _isSuperAdmin = false;
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (SupabaseConfig.isConfigured) {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email.trim(),
          password: password.trim(),
        );

        if (response.session != null) {
          _currentUser = response.user;
          _isAuthenticated = true;
          _isDemoMode = false;

          // Store refresh token safely
          if (response.session!.refreshToken != null) {
            await _safeStorageWrite(_keyToken, response.session!.refreshToken);
          }

          await _resolveCafeId();
          await _checkSuperAdminStatus();
          _isLoading = false;
          notifyListeners();
          return true;
        }
      } else {
        // Fallback: If Supabase credentials are not yet entered, sign in as Demo Owner
        await demoLogin();
        return true;
      }
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid login credentials')) {
        _errorMessage = 'Invalid email or password. Please check your credentials and try again.';
      } else if (e.message.toLowerCase().contains('email not confirmed')) {
        _errorMessage = 'Email not confirmed yet. Please verify your email or turn off "Confirm email" in Supabase Auth.';
      } else {
        _errorMessage = e.message;
      }
    } catch (e) {
      _errorMessage = 'Login failed: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String cafeName,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (SupabaseConfig.isConfigured) {
        final response = await Supabase.instance.client.auth.signUp(
          email: email.trim(),
          password: password.trim(),
          data: {'cafe_name': cafeName.trim()},
        );

        if (response.user != null) {
          _currentUser = response.user;

          if (response.session != null) {
            _isAuthenticated = true;
            _isDemoMode = false;
            if (response.session!.refreshToken != null) {
              await _safeStorageWrite(_keyToken, response.session!.refreshToken);
            }
            await _createCafeForNewOwner(cafeName.trim());
            _isLoading = false;
            notifyListeners();
            return true;
          } else {
            // Account created or already exists. Attempt immediate sign-in with provided password.
            final autoLogin = await Supabase.instance.client.auth.signInWithPassword(
              email: email.trim(),
              password: password.trim(),
            );

            if (autoLogin.session != null) {
              _currentUser = autoLogin.user;
              _isAuthenticated = true;
              _isDemoMode = false;
              if (autoLogin.session!.refreshToken != null) {
                await _safeStorageWrite(_keyToken, autoLogin.session!.refreshToken);
              }
              await _resolveCafeId();
              _isLoading = false;
              notifyListeners();
              return true;
            }

            _errorMessage = 'Account created! Please confirm email or turn off "Confirm email" in Supabase Auth settings for instant sign-in.';
            _isLoading = false;
            notifyListeners();
            return false;
          }
        }
      } else {
        await demoLogin();
        return true;
      }
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('rate limit')) {
        _errorMessage = 'Email rate limit reached. Please sign in directly or turn off "Confirm email" in Supabase Auth.';
      } else {
        _errorMessage = e.message;
      }
    } catch (e) {
      _errorMessage = 'Sign up error: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> demoLogin() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 300));
    _isAuthenticated = true;
    _isDemoMode = true;
    _cafeId = SupabaseConfig.demoCafeId;
    _cafeName = SupabaseConfig.demoCafeName;
    _isCafeProfileLoaded = true;
    await _safeStorageWrite(_keyDemoAuth, 'true');

    _isLoading = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (SupabaseConfig.isConfigured) {
        await Supabase.instance.client.auth.signOut();
      }
      await _safeStorageDelete(_keyToken);
      await _safeStorageDelete(_keyDemoAuth);
    } catch (e) {
      debugPrint('Sign out error: $e');
    } finally {
      _currentUser = null;
      _isAuthenticated = false;
      _isDemoMode = false;
      _isSuperAdmin = false;
      _superAdminViewMode = true;
      _cafeId = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _createCafeForNewOwner(String name) async {
    if (_currentUser == null) return;
    try {
      final cafeNameVal = name.isNotEmpty ? name : 'My Artisan Cafe';
      final cafeRes = await Supabase.instance.client.from('cafes').insert({
        'name': cafeNameVal,
        'owner_id': _currentUser!.id,
      }).select('id, name').single();

      _cafeId = cafeRes['id'] as String;
      _cafeName = (cafeRes['name'] as String?) ?? cafeNameVal;

      // Automatically create 5 dining tables with QR tokens for this cafe
      final List<Map<String, dynamic>> defaultTables = [];
      for (int i = 1; i <= 5; i++) {
        defaultTables.add({
          'cafe_id': _cafeId,
          'table_number': i,
        });
      }
      await Supabase.instance.client.from('tables').insert(defaultTables);
    } catch (e) {
      debugPrint('Error creating initial cafe & tables: $e');
      await _resolveCafeId();
    }
  }

  Future<void> _resolveCafeId() async {
    if (!SupabaseConfig.isConfigured || _currentUser == null) {
      _cafeId = SupabaseConfig.demoCafeId;
      _cafeName = SupabaseConfig.demoCafeName;
      _isCafeProfileLoaded = true;
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('cafes')
          .select('id, name')
          .eq('owner_id', _currentUser!.id)
          .maybeSingle();

      final metaCafeName = (_currentUser!.userMetadata?['cafe_name'] as String?)?.trim();

      if (data != null && data['id'] != null) {
        _cafeId = data['id'] as String;
        final dbName = (data['name'] as String?)?.trim();
        _cafeName = (dbName != null && dbName.isNotEmpty) ? dbName : (metaCafeName ?? 'My Cafe');
        _isCafeProfileLoaded = true;
      } else {
        // Auto-create initial cafe entry for this owner if none exists
        final initialName = (metaCafeName != null && metaCafeName.isNotEmpty) ? metaCafeName : 'My Cafe';
        final inserted = await Supabase.instance.client.from('cafes').insert({
          'name': initialName,
          'owner_id': _currentUser!.id,
        }).select('id, name').single();

        _cafeId = inserted['id'] as String;
        _cafeName = (inserted['name'] as String?) ?? initialName;
        _isCafeProfileLoaded = true;

        // Add 5 tables
        final List<Map<String, dynamic>> defaultTables = [];
        for (int i = 1; i <= 5; i++) {
          defaultTables.add({'cafe_id': _cafeId, 'table_number': i});
        }
        await Supabase.instance.client.from('tables').insert(defaultTables);
      }
    } catch (e) {
      debugPrint('Error resolving cafe ID: $e');
      _errorMessage = 'Your cafe profile could not be loaded.';
      _cafeName = 'Your cafe profile could not be loaded.';
      _isCafeProfileLoaded = false;
    }
  }

  Future<bool> updateCafeName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return false;
    _cafeName = trimmed;
    notifyListeners();

    if (!SupabaseConfig.isConfigured || _isDemoMode || _cafeId == null) {
      return true;
    }

    try {
      await Supabase.instance.client
          .from('cafes')
          .update({'name': trimmed})
          .eq('id', _cafeId!);
      return true;
    } catch (e) {
      debugPrint('Error updating cafe name: $e');
      return false;
    }
  }

}
