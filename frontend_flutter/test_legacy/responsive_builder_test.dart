@Skip('Moved to legacy; not part of minimal CI smoke suite.')
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hackit_mvp_flutter/utils/responsive_builder.dart';

void main() {
  group('ResponsiveBuilder Tests', () {
    testWidgets('Detects mobile layout correctly', (WidgetTester tester) async {
      DeviceType? detectedType;
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveBuilder(
            builder: (context, deviceType) {
              detectedType = deviceType;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(detectedType, DeviceType.mobile);
    });

    testWidgets('Detects tablet layout correctly', (WidgetTester tester) async {
      DeviceType? detectedType;
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveBuilder(
            builder: (context, deviceType) {
              detectedType = deviceType;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(detectedType, DeviceType.tablet);
    });

    testWidgets('Detects desktop layout correctly',
        (WidgetTester tester) async {
      DeviceType? detectedType;
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveBuilder(
            builder: (context, deviceType) {
              detectedType = deviceType;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(detectedType, DeviceType.desktop);
    });

    testWidgets('Responds to size changes', (WidgetTester tester) async {
      DeviceType? detectedType;
      const key = Key('responsive_container');

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ResponsiveBuilder(
              builder: (context, deviceType) {
                detectedType = deviceType;
                return Container(key: key);
              },
            ),
          ),
        ),
      );

      // Start with mobile size
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pump();
      expect(detectedType, DeviceType.mobile);

      // Change to tablet size
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pump();
      expect(detectedType, DeviceType.tablet);

      // Change to desktop size
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      await tester.pump();
      expect(detectedType, DeviceType.desktop);
    });
  });
}
