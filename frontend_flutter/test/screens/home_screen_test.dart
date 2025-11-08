import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hackit_mvp_flutter/providers/search_provider.dart';
import 'package:hackit_mvp_flutter/models/search_result.dart';
import 'package:hackit_mvp_flutter/screens/home_screen.dart';

void main() {
  group('HomeScreen Integration Tests', () {
    late SearchProvider mockProvider;

    setUp(() {
      mockProvider = SearchProvider();
    });

    testWidgets('shows loading state', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<SearchProvider>.value(
          value: mockProvider,
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      mockProvider.loading = true;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<SearchProvider>.value(
          value: mockProvider,
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      mockProvider.error = 'Test error';
      await tester.pump();

      expect(find.text('❌ Test error'), findsOneWidget);
    });

    testWidgets('handles successful search', (WidgetTester tester) async {
      final navigator = MockNavigator();
      
      await tester.pumpWidget(
        ChangeNotifierProvider<SearchProvider>.value(
          value: mockProvider,
          child: MaterialApp(
            home: const HomeScreen(),
            onGenerateRoute: navigator.onGenerateRoute,
          ),
        ),
      );

      mockProvider.result = const SearchResult(
        title: 'Test Result',
        steps: ['Step 1'],
        videoUrl: 'https://example.com',
        source: 'Test'
      );
      await tester.pump();

      expect(navigator.pushNamedCalled, true);
      expect(navigator.pushedRoute, '/result');
    });
  });
}

class MockNavigator {
  bool pushNamedCalled = false;
  String? pushedRoute;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    pushNamedCalled = true;
    pushedRoute = settings.name;
    return MaterialPageRoute(
      builder: (_) => Container(),
      settings: settings,
    );
  }
}