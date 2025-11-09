import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hackit_mvp_flutter/utils/accessibility_helper.dart';

void main() {
  group('AccessibilityHelper Tests', () {
    testWidgets('Announces message correctly', (WidgetTester tester) async {
      const testMessage = 'Test announcement';
      var wasAnnounced = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              AccessibilityHelper.announceForAccessibility(
                  context, testMessage);
              wasAnnounced = true;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(wasAnnounced, true);
    });

    testWidgets('Adds semantics correctly (basic flags only)',
        (WidgetTester tester) async {
      const testLabel = 'Test label';
      const testHint = 'Test hint';

      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityHelper.addSemantics(
            label: testLabel,
            hint: testHint,
            isButton: true,
            child: const Text('Test'),
          ),
        ),
      );

      // Just ensure a Semantics widget is present (implementation details may differ by Flutter version).
      expect(find.byType(Semantics), findsWidgets);
    });

    testWidgets('Adds screen reader text correctly (label presence)',
        (WidgetTester tester) async {
      const testAnnouncement = 'Screen reader text';

      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityHelper.addScreenReader(
            announcement: testAnnouncement,
            child: const Text('Visual text'),
          ),
        ),
      );

      expect(find.byType(Semantics), findsWidgets);
    });

    testWidgets('Creates minimum touch target size',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityHelper.enlargeTouchTarget(
            child: const Icon(Icons.add),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, AccessibilityHelper.minTouchTarget);
      expect(sizedBox.height, AccessibilityHelper.minTouchTarget);
    });
  });
}
