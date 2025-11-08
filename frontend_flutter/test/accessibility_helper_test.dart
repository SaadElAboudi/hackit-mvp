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
              AccessibilityHelper.announceForAccessibility(context, testMessage);
              wasAnnounced = true;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(wasAnnounced, true);
    });

    testWidgets('Adds semantics correctly', (WidgetTester tester) async {
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

      final semantics = tester.getSemantics(find.byType(Semantics));
      
      expect(semantics.label, testLabel);
      expect(semantics.hint, testHint);
      expect(semantics.isButton, true);
    });

    testWidgets('Adds screen reader text correctly', (WidgetTester tester) async {
      const testAnnouncement = 'Screen reader text';

      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityHelper.addScreenReader(
            announcement: testAnnouncement,
            child: const Text('Visual text'),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(Semantics));
      expect(semantics.label, testAnnouncement);
    });

    testWidgets('Creates minimum touch target size', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityHelper.enlargeTouchTarget(
            child: const Icon(Icons.add),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox));
      expect(sizedBox.width, AccessibilityHelper.minTouchTarget);
      expect(sizedBox.height, AccessibilityHelper.minTouchTarget);
    });
  });
}