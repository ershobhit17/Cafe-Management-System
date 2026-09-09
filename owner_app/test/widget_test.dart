import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:owner_app/main.dart';
import 'package:owner_app/services/auth_service.dart';
import 'package:owner_app/services/cafe_service.dart';
import 'package:owner_app/services/earnings_service.dart';
import 'package:owner_app/services/menu_service.dart';
import 'package:owner_app/services/order_service.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => CafeService()),
          ChangeNotifierProvider(create: (_) => MenuService()),
          ChangeNotifierProvider(create: (_) => OrderService()),
          ChangeNotifierProvider(create: (_) => EarningsService()),
        ],
        child: const CafeOwnerApp(),
      ),
    );
    expect(find.byType(CafeOwnerApp), findsOneWidget);
  });
}
