import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/widgets/chat_bubbles.dart';

void main() {
  group('UserBubble', () {
    testWidgets('renders text and no actions when none provided',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserBubble(text: 'Hello world')),
      ));
      expect(find.text('Hello world'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });

    testWidgets('renders edit and regenerate actions', (tester) async {
      var editTapped = false;
      var regenTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UserBubble(
            text: 'Query',
            onEdit: () => editTapped = true,
            onRegenerate: () => regenTapped = true,
          ),
        ),
      ));
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();

      expect(editTapped, isTrue);
      expect(regenTapped, isTrue);
    });

    testWidgets('disabled actions do not trigger callbacks', (tester) async {
      var editTapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UserBubble(
            text: 'Disabled',
            onEdit: () => editTapped = true,
            disabled: true,
          ),
        ),
      ));
      final editButton = find.byIcon(Icons.edit_rounded);
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      await tester.pump();
      expect(editTapped, isFalse);
    });
  });
}
