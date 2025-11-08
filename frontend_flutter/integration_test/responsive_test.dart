import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hackit_mvp_flutter/main.dart';
import 'package:hackit_mvp_flutter/utils/responsive_builder.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late MockSharedPreferences mockPrefs;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    when(() => mockPrefs.getString(any())).thenReturn(null);
    when(() => mockPrefs.setString(any(), any())).thenAnswer((_) async => true);
  });

  group('Responsive Layout Tests', () {
    testWidgets('Mobile layout test', (tester) async {
      // Set mobile screen size
      await tester.binding.setSurfaceSize(const Size(375, 812)); // iPhone X size

      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();

      // Verify mobile layout
      expect(find.byType(TextField), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, 1);
    });

    testWidgets('Tablet layout test', (tester) async {
      // Set tablet screen size
      await tester.binding.setSurfaceSize(const Size(834, 1194)); // iPad Pro 11" size

      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();

      // Verify tablet layout
      expect(find.byType(TextField), findsOneWidget);
      // Add tablet-specific layout checks
    });

    testWidgets('Desktop layout test', (tester) async {
      // Set desktop screen size
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();

      // Verify desktop layout
      expect(find.byType(TextField), findsOneWidget);
      // Add desktop-specific layout checks
    });

    testWidgets('Orientation changes test', (tester) async {
      // Start with portrait
      await tester.binding.setSurfaceSize(const Size(375, 812));
      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();

      // Record portrait layout
      final portraitLayout = tester.getRect(find.byType(TextField));

      // Switch to landscape
      await tester.binding.setSurfaceSize(const Size(812, 375));
      await tester.pumpAndSettle();

      // Record landscape layout
      final landscapeLayout = tester.getRect(find.byType(TextField));

      // Verify layout adapted
      expect(portraitLayout, isNot(equals(landscapeLayout)));
    });
  });
}