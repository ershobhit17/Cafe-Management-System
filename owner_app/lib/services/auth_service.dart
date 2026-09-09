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
  String _cafeName = 'Aroma Artisan Cafe';

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isDemoMode => _isDemoMode;
  String? get errorMessage => _errorMessage;
  User? get currentUser => _currentUser;
  String get currentCafeId => _cafeId ?? SupabaseConfig.demoCafeId;
  String get currentCafeName => _cafeName;

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
      return;
    }

    try {
      var data = await Supabase.instance.client
          .from('cafes')
          .select('id, name')
          .eq('owner_id', _currentUser!.id)
          .maybeSingle();

      if (data == null) {
        // Claim the unowned seed cafe if available
        final unowned = await Supabase.instance.client
            .from('cafes')
            .select('id, name')
            .filter('owner_id', 'is', 'null')
            .maybeSingle();

        if (unowned != null && unowned['id'] != null) {
          final claimId = unowned['id'] as String;
          await Supabase.instance.client
              .from('cafes')
              .update({'owner_id': _currentUser!.id})
              .eq('id', claimId);
          data = unowned;
        }
      }

      if (data != null && data['id'] != null) {
        _cafeId = data['id'] as String;
        _cafeName = (data['name'] as String?) ?? 'Aroma Artisan Cafe';
      } else {
        // Auto-create initial cafe entry for this owner if none exists
        final inserted = await Supabase.instance.client.from('cafes').insert({
          'name': 'My Cafe',
          'owner_id': _currentUser!.id,
        }).select('id, name').single();

        _cafeId = inserted['id'] as String;
        _cafeName = (inserted['name'] as String?) ?? 'My Cafe';

        // Add 5 tables
        final List<Map<String, dynamic>> defaultTables = [];
        for (int i = 1; i <= 5; i++) {
          defaultTables.add({'cafe_id': _cafeId, 'table_number': i});
        }
        await Supabase.instance.client.from('tables').insert(defaultTables);
      }
    } catch (e) {
      debugPrint('Error resolving cafe ID: $e');
      _cafeId = SupabaseConfig.demoCafeId;
      _cafeName = SupabaseConfig.demoCafeName;
    }
  }
}
