import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hackit_mvp_flutter/main.dart';
import 'package:hackit_mvp_flutter/services/cache_manager.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt.unregister<SharedPreferences>();
    }
    if (getIt.isRegistered<CacheManager>()) {
      getIt.unregister<CacheManager>();
    }
    getIt.registerSingleton<SharedPreferences>(prefs);
    getIt.registerSingleton<CacheManager>(CacheManager(prefs));
  });

  testWidgets('Smoke: MyApp builds root MaterialApp', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MyApp), findsOneWidget);
    // Ensure a MaterialApp exists
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
