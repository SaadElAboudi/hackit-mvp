import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/screens/home_screen.dart';
import 'package:hackit_mvp_flutter/providers/search_provider.dart';
import 'package:hackit_mvp_flutter/models/chat_message.dart';

class TestSearchProvider extends SearchProvider {
  int calls = 0;
  TestSearchProvider() : super();

  @override
  Future<void> search(String query) async {
    calls += 1;
    lastQuery = query;
    // Avoid network: directly append a synthetic assistant steps message.
    messages = [
      ...messages,
      ChatMessage.assistantSteps('synthetic', 'Title', const ['S1'],
          source: 'youtube-api'),
    ];
    notifyListeners();
  }
}

void main() {
  group('HomeScreen SourceChip & Retry', () {
    testWidgets('renders source chip for assistant steps with source',
        (tester) async {
      final provider = TestSearchProvider();
      provider.messages = [
        ChatMessage.assistantSteps(
          '1',
          'A title',
          const ['Step'],
          source: 'youtube-api',
        ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<SearchProvider>.value(
          value: provider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('youtube-api'), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    });

    testWidgets('Retry button disabled when no lastQuery', (tester) async {
      final provider = TestSearchProvider();
      provider.lastQuery = null; // ensure no last prompt
      provider.messages = [
        ChatMessage.assistantError('e1', 'Erreur de test'),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<SearchProvider>.value(
          value: provider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final retry = find.text('Réessayer');
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pump();
      expect(provider.calls, 0);
    });

    testWidgets('Retry button calls provider.search when enabled',
        (tester) async {
      final provider = TestSearchProvider();
      provider.lastQuery = 'how to code';
      provider.messages = [
        ChatMessage.assistantError('e2', 'Erreur de test'),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<SearchProvider>.value(
          value: provider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Réessayer'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      expect(provider.calls, 1);
    });
  });
}
