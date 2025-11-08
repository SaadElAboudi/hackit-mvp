import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/widgets/chat_input.dart';

void main() {
  group('ChatInput Widget Tests', () {
    testWidgets('renders correctly with default props', (WidgetTester tester) async {
      bool searchCalled = false;
      String? searchQuery;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSearch: (query) {
              searchCalled = true;
              searchQuery = query;
            },
          ),
        ),
      ));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Rechercher'), findsOneWidget);
    });

    testWidgets('handles empty input correctly', (WidgetTester tester) async {
      bool searchCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSearch: (_) => searchCalled = true,
          ),
        ),
      ));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(searchCalled, isFalse);
    });

    testWidgets('calls onSearch with trimmed input', (WidgetTester tester) async {
      String? capturedQuery;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSearch: (query) => capturedQuery = query,
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), '  test query  ');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(capturedQuery, 'test query');
    });

    testWidgets('disables input when disabled=true', (WidgetTester tester) async {
      bool searchCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSearch: (_) => searchCalled = true,
            disabled: true,
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), 'test');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(searchCalled, isFalse);
      expect((tester.widget(find.byType(ElevatedButton)) as ElevatedButton).enabled, isFalse);
    });
  });
}