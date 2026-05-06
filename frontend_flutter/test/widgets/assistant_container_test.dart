import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/widgets/chat_bubbles.dart';

void main() {
  group('AssistantContainer', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AssistantContainer(
            child: Text('Assistant content'),
          ),
        ),
      ));

      expect(find.byType(AssistantContainer), findsOneWidget);
      expect(find.text('Assistant content'), findsOneWidget);
    });
  });
}
