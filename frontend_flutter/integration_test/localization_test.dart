import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// TEMP DISABLED: incorrect package name; will restore after refactor.
// import 'package:hackit_mvp_flutter/main.dart' as app;
import 'package:intl/intl.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Localization Tests', () {
    testWidgets('supports French localization', (tester) async {
      await tester.binding.setLocale('fr', 'FR');
      app.main();
      await tester.pumpAndSettle();

      // Vérifier les textes traduits
      expect(find.text('Rechercher'), findsOneWidget);
      expect(find.text('Résultats'), findsOneWidget);

      // Vérifier le format de date
      final dateString = DateFormat.yMMMd('fr').format(DateTime.now());
      expect(
        find.textContaining(RegExp(r'\d{1,2} \w+ \d{4}')),
        findsOneWidget,
      );
    });

    testWidgets('supports English localization', (tester) async {
      await tester.binding.setLocale('en', 'US');
      app.main();
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Results'), findsOneWidget);
    });

    testWidgets('supports RTL layout', (tester) async {
      await tester.binding.setLocale('ar', 'SA');
      app.main();
      await tester.pumpAndSettle();

      // Vérifier la direction du texte
      final textDirection = tester
          .widget<Directionality>(
            find.byType(Directionality).first,
          )
          .textDirection;

      expect(textDirection, TextDirection.rtl);

      // Vérifier l'alignement des éléments
      final searchField = tester.widget<TextField>(
        find.byType(TextField),
      );
      expect(searchField.textAlign, TextAlign.right);

      // Vérifier la mise en page RTL
      final iconPosition = tester
          .getTopRight(
            find.byIcon(Icons.search),
          )
          .dx;
      final fieldPosition = tester
          .getTopRight(
            find.byType(TextField),
          )
          .dx;
      expect(iconPosition < fieldPosition, true);
    });

    testWidgets('supports number formatting', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Test avec différents formats de nombre selon les locales
      final locales = ['fr_FR', 'en_US', 'de_DE'];

      for (final locale in locales) {
        await tester.binding.setLocale(
          locale.split('_')[0],
          locale.split('_')[1],
        );
        await tester.pumpAndSettle();

        const number = 1234567.89;
        final formattedNumber =
            NumberFormat.decimalPattern(locale).format(number);

        expect(
          find.textContaining(formattedNumber),
          findsOneWidget,
          reason: 'Number format incorrect for locale $locale',
        );
      }
    });

    testWidgets('supports dynamic text direction', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Test de mélange de texte LTR et RTL
      await tester.enterText(
        find.byType(TextField),
        'Hello مرحبا',
      );
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byType(TextField),
      );

      expect(
        textField.textDirection,
        isNotNull,
        reason: 'Text direction should be automatically determined',
      );
    });
  });
}
