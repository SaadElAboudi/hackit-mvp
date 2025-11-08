import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hackit_mvp_flutter/main.dart';
import 'package:hackit_mvp_flutter/services/performance_monitor.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late MockSharedPreferences mockPrefs;
  late PerformanceMonitor monitor;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    when(() => mockPrefs.getString(any())).thenReturn(null);
    when(() => mockPrefs.setString(any(), any())).thenAnswer((_) async => true);
    
    monitor = PerformanceMonitor();
    monitor.clearMetrics();
  });

  group('Performance Tests', () {
    testWidgets('Initial load performance', (tester) async {
      monitor.startOperation('app_launch');
      
      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();
      
      monitor.stopOperation('app_launch');
      
      final metrics = monitor.getAverageMetrics();
      expect(metrics['app_launch']!, lessThan(1000)); // Should launch under 1s
    });

    testWidgets('Search input performance', (tester) async {
      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();

      monitor.startOperation('search_input');
      
      // Type search query
      await tester.enterText(find.byType(TextField), 'performance test query');
      await tester.pumpAndSettle();
      
      monitor.stopOperation('search_input');
      
      final metrics = monitor.getAverageMetrics();
      expect(metrics['search_input']!, lessThan(100)); // Input should be responsive
    });

    testWidgets('Navigation performance', (tester) async {
      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();

      // Setup some mock results
      await tester.enterText(find.byType(TextField), 'test');
      await tester.tap(find.text('Rechercher'));
      await tester.pumpAndSettle();

      monitor.startOperation('navigation');
      
      // Navigate back and forth
      await tester.tap(find.text('← Nouvelle recherche'));
      await tester.pumpAndSettle();
      
      monitor.stopOperation('navigation');
      
      final metrics = monitor.getAverageMetrics();
      expect(metrics['navigation']!, lessThan(500)); // Navigation should be smooth
    });

    testWidgets('Memory usage test', (tester) async {
      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      await tester.pumpAndSettle();

      final startMemory = await IntegrationTestWidgetsFlutterBinding.instance
          .watchPerformance(() async {
        // Perform multiple searches
        for (var i = 0; i < 5; i++) {
          await tester.enterText(find.byType(TextField), 'test $i');
          await tester.tap(find.text('Rechercher'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('← Nouvelle recherche'));
          await tester.pumpAndSettle();
        }
      });

      // Verify no significant memory leaks
      expect(startMemory.maxRss, lessThan(100 * 1024 * 1024)); // Less than 100MB
    });

    testWidgets('Frame rendering performance', (tester) async {
      await tester.pumpWidget(MyApp(prefs: mockPrefs, cacheManager: null));
      
      final frameMonitor = await IntegrationTestWidgetsFlutterBinding.instance
          .watchPerformance(() async {
        // Perform actions that might cause frame drops
        await tester.fling(
          find.byType(ListView), 
          const Offset(0, -500), 
          3000
        );
        await tester.pumpAndSettle();
      });

      // Verify smooth scrolling
      expect(frameMonitor.frameCount, greaterThan(0));
      expect(
        frameMonitor.missed99thPercentile, 
        lessThan(frameMonitor.frameCount * 0.01)
      ); // Less than 1% dropped frames
    });
  });
}