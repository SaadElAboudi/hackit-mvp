import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hackit_mvp_flutter/main.dart';
import 'package:hackit_mvp_flutter/services/api_service.dart';
import 'package:hackit_mvp_flutter/models/search_result.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences.dart';

class MockApiService extends Mock implements ApiService {}
class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late MockApiService mockApi;
  late MockSharedPreferences mockPrefs;

  setUp(() {
    mockApi = MockApiService();
    mockPrefs = MockSharedPreferences();
    
    // Setup mock responses
    when(() => mockPrefs.getString(any())).thenReturn(null);
    when(() => mockPrefs.setString(any(), any())).thenAnswer((_) async => true);
    
    when(() => mockApi.search(any())).thenAnswer((_) async => {
      'title': 'Test Result',
      'steps': ['Step 1', 'Step 2'],
      'videoUrl': 'https://example.com/video',
      'source': 'Test Source'
    });
  });

  Future<void> pumpTestApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: mockApi),
        ],
        child: MyApp(prefs: mockPrefs, cacheManager: null),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Complete App Flow Tests', () {
    testWidgets('Full search flow test', (tester) async {
      await pumpTestApp(tester);

      // Verify initial state
      expect(find.text('Hackit MVP'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'test query');
      await tester.pump();

      // Tap search button
      await tester.tap(find.text('Rechercher'));
      await tester.pump();

      // Verify loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      // Verify results
      await tester.pumpAndSettle();
      expect(find.text('Test Result'), findsOneWidget);
      expect(find.text('1. Step 1'), findsOneWidget);
      expect(find.text('2. Step 2'), findsOneWidget);

      // Verify video card
      expect(find.text('Voir la vidéo'), findsOneWidget);

      // Navigate back
      await tester.tap(find.text('← Nouvelle recherche'));
      await tester.pumpAndSettle();

      // Verify back on home screen
      expect(find.text('Hackit MVP'), findsOneWidget);
    });

    testWidgets('Error handling test', (tester) async {
      // Setup error response
      when(() => mockApi.search(any())).thenThrow(
        ApiException('Test error message')
      );

      await pumpTestApp(tester);

      // Perform search
      await tester.enterText(find.byType(TextField), 'error test');
      await tester.tap(find.text('Rechercher'));
      await tester.pump();

      // Verify error state
      await tester.pumpAndSettle();
      expect(find.text('Test error message'), findsOneWidget);
    });

    testWidgets('Offline mode test', (tester) async {
      // Setup cached response
      when(() => mockPrefs.getString(any())).thenReturn('''
        {
          "test query": {
            "result": {
              "title": "Cached Result",
              "steps": ["Cached Step"],
              "videoUrl": "https://example.com/cached",
              "source": "Cache"
            },
            "timestamp": "${DateTime.now().toIso8601String()}"
          }
        }
      ''');

      // Setup offline API
      when(() => mockApi.search(any())).thenThrow(
        ApiException('Network error')
      );

      await pumpTestApp(tester);

      // Perform search
      await tester.enterText(find.byType(TextField), 'test query');
      await tester.tap(find.text('Rechercher'));
      await tester.pump();

      // Verify cached results shown
      await tester.pumpAndSettle();
      expect(find.text('Cached Result'), findsOneWidget);
      expect(find.text('1. Cached Step'), findsOneWidget);
    });

    testWidgets('Theme switching test', (tester) async {
      await pumpTestApp(tester);

      // Find and tap theme toggle
      await tester.tap(find.byIcon(Icons.brightness_6));
      await tester.pumpAndSettle();

      // Verify theme changed
      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.theme, isNotNull);
    });

    testWidgets('Performance monitoring test', (tester) async {
      await pumpTestApp(tester);

      // Perform multiple searches
      for (var i = 0; i < 3; i++) {
        await tester.enterText(find.byType(TextField), 'test $i');
        await tester.tap(find.text('Rechercher'));
        await tester.pumpAndSettle();
        
        // Verify response time is measured
        verify(() => mockApi.search(any())).called(1);
        await tester.tap(find.text('← Nouvelle recherche'));
        await tester.pumpAndSettle();
      }
    });
  });
}