import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_nav_screen.dart';
import 'services/auth_service.dart';
import 'services/cafe_service.dart';
import 'services/earnings_service.dart';
import 'services/menu_service.dart';
import 'services/order_service.dart';
import 'services/sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase if configured with cloud credentials
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        anonKey: SupabaseConfig.supabaseAnonKey,
      );
      debugPrint('Supabase initialized successfully.');
    } catch (e) {
      debugPrint('Supabase init warning: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..initializeAuth()),
        ChangeNotifierProvider(create: (_) => CafeService()),
        ChangeNotifierProvider(create: (_) => MenuService()),
        ChangeNotifierProvider(create: (_) => OrderService()),
        ChangeNotifierProvider(create: (_) => EarningsService()),
        ChangeNotifierProvider(create: (_) => SoundService.instance),
      ],
      child: const CafeOwnerApp(),
    ),
  );
}

class CafeOwnerApp extends StatelessWidget {
  const CafeOwnerApp({super.key});

  static const Color primaryOrange = Color(0xFFFF7A00);
  static const Color primaryOrangeLight = Color(0xFFFF8C42);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cafe Owner Portal',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      // Light Theme
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryOrange,
          primary: primaryOrange,
          surface: const Color(0xFFFFFFFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFBFBFD),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF1A1A1A),
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFF0E6DD), width: 1),
          ),
        ),
      ),
      // Dark Theme
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryOrangeLight,
          primary: primaryOrangeLight,
          surface: const Color(0xFF1E1E1E),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Color(0xFFF5F5F5),
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF2E2E2E), width: 1),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF7A00)),
        ),
      );
    }

    if (auth.isAuthenticated) {
      return const MainNavScreen();
    }

    return const LoginScreen();
  }
}
