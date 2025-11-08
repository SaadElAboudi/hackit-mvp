import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hackit_mvp_flutter/services/accessibility_service.dart';
import '../test/helpers/test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Accessibility Tests', () {
    testWidgets('supports screen readers', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Vérifier les labels d'accessibilité
      expect(
        tester.getSemantics(find.byType(TextField)),
        matchesSemantics(
          label: 'Champ de recherche',
          isTextField: true,
          hasTapAction: true,
        ),
      );

      // Vérifier la taille des zones tactiles
      final searchButton = find.byType(IconButton);
      final buttonSize = tester.getSize(searchButton);
      expect(
        buttonSize.width >= 48 && buttonSize.height >= 48,
        true,
        reason: 'Touch target size should be at least 48x48',
      );

      // Vérifier l'ordre de lecture logique
      final List<String> expectedOrder = [
        'Titre de l\'application',
        'Champ de recherche',
        'Bouton de recherche',
      ];

      final semanticsNodes = collectSemantics(tester);
      for (var i = 0; i < expectedOrder.length; i++) {
        expect(
          semanticsNodes[i].label,
          expectedOrder[i],
          reason: 'Incorrect reading order',
        );
      }
    });

    testWidgets('supports text scaling', (tester) async {
      await tester.binding.setTextScaleFactor(2.0);
      app.main();
      await tester.pumpAndSettle();

      // Vérifier que le texte est lisible avec un zoom x2
      final textFields = find.byType(Text).evaluate();
      for (final textField in textFields) {
        final widget = textField.widget as Text;
        final textPainter = TextPainter(
          text: TextSpan(text: widget.data, style: widget.style),
          textDirection: TextDirection.ltr,
        )..layout();
        
        expect(
          textPainter.height >= 24,
          true,
          reason: 'Text should be readable when scaled',
        );
      }
    });

    testWidgets('supports high contrast', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Vérifier les ratios de contraste
      final coloredWidgets = find.byWidgetPredicate((widget) {
        return widget is Container || widget is Text;
      }).evaluate();

      for (final widget in coloredWidgets) {
        if (widget.widget is Text) {
          final text = widget.widget as Text;
          final style = text.style;
          if (style?.color != null) {
            final backgroundColor = tester.getBackgroundColor(widget);
            final contrastRatio = calculateContrastRatio(
              style!.color!,
              backgroundColor,
            );
            expect(
              contrastRatio >= 4.5,
              true,
              reason: 'Text contrast ratio should be at least 4.5:1',
            );
          }
        }
      }
    });

    testWidgets('supports keyboard navigation', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Focus initial sur le champ de recherche
      expect(
        find.byType(TextField),
        hasKeyboardFocus,
      );

      // Navigation avec Tab
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.search),
        hasKeyboardFocus,
      );

      // Activation avec Entrée
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      
      // Vérifier que l'action a été déclenchée
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
      );
    });
  });
}

double calculateContrastRatio(Color foreground, Color background) {
  double l1 = computeLuminance(foreground);
  double l2 = computeLuminance(background);
  
  double lightest = max(l1, l2);
  double darkest = min(l1, l2);
  
  return (lightest + 0.05) / (darkest + 0.05);
}

double computeLuminance(Color color) {
  final r = color.red / 255;
  final g = color.green / 255;
  final b = color.blue / 255;
  
  final rs = r <= 0.03928 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4);
  final gs = g <= 0.03928 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4);
  final bs = b <= 0.03928 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4);
  
  return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs;
}