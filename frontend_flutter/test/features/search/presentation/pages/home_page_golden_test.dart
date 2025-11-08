import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:hackit_mvp/features/search/presentation/pages/home_page.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
  });

  testGoldens('HomePage - different states', (tester) async {
    final builder = DeviceBuilder()
      ..overrideDevicesForAllScenarios(
        devices: [
          Device.phone,
          Device.tablet,
          Device.iphone11,
        ],
      )
      ..addScenario(
        widget: const HomePage(),
        name: 'initial_state',
      );

    await tester.pumpDeviceBuilder(builder);
    await screenMatchesGolden(tester, 'home_page_states');
  });

  testGoldens('HomePage - dark mode', (tester) async {
    final builder = DeviceBuilder()
      ..overrideDevicesForAllScenarios(
        devices: [Device.phone],
      )
      ..addScenario(
        widget: const HomePage(),
        name: 'dark_mode',
      );

    await tester.pumpDeviceBuilder(
      builder,
      wrapper: (child) => materialAppWrapper(
        theme: ThemeData.dark(),
        child: child,
      ),
    );

    await screenMatchesGolden(tester, 'home_page_dark');
  });
}