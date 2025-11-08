import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/widgets/chat_bubbles.dart';
import 'package:hackit_mvp_flutter/widgets/summary_view.dart';

void main() {
  group('AssistantContainer', () {
    testWidgets('renders child content (SummaryView inside)', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AssistantContainer(
            child: SummaryView(title: 'Title', steps: ['Step 1', 'Step 2']),
          ),
        ),
      ));

      expect(find.byType(AssistantContainer), findsOneWidget);
      expect(find.byType(SummaryView), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('1. Step 1'), findsOneWidget);
      expect(find.text('2. Step 2'), findsOneWidget);
    });
  });
}
