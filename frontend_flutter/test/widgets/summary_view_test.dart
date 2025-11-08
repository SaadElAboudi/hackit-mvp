import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/widgets/summary_view.dart';

void main() {
  group('SummaryView Widget Tests', () {
    testWidgets('renders title and steps correctly', (WidgetTester tester) async {
      const title = 'Test Title';
      const steps = ['Step 1', 'Step 2', 'Step 3'];

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SummaryView(
            title: title,
            steps: steps,
          ),
        ),
      ));

      expect(find.text(title), findsOneWidget);
      expect(find.text('1. ${steps[0]}'), findsOneWidget);
      expect(find.text('2. ${steps[1]}'), findsOneWidget);
      expect(find.text('3. ${steps[2]}'), findsOneWidget);
    });

    testWidgets('handles empty steps list', (WidgetTester tester) async {
      const title = 'Test Title';

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SummaryView(
            title: title,
            steps: [],
          ),
        ),
      ));

      expect(find.text(title), findsOneWidget);
      expect(find.text('Étapes :'), findsNothing);
    });

    testWidgets('renders with correct styling', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SummaryView(
            title: 'Title',
            steps: ['Step'],
          ),
        ),
      ));

      final card = find.byType(Card);
      expect(card, findsOneWidget);
      
      final titleWidget = find.text('Title');
      final titleStyle = tester.widget<Text>(titleWidget).style;
      expect(titleStyle?.fontSize, 20);
      expect(titleStyle?.fontWeight, FontWeight.bold);
    });
  });
}