import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hackit_mvp_flutter/providers/search_provider.dart';
import 'package:hackit_mvp_flutter/widgets/chat_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ChatInput prompt templates', () {
    testWidgets('Selecting a chip transforms text and is used on submit',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = SearchProvider(prefs: prefs, testMode: true);
      String? submitted;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<SearchProvider>.value(
            value: provider,
            child: Scaffold(
              body: ChatInput(
                onSearch: (q) => submitted = q,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter initial text
      final tf = find.byType(TextField);
      expect(tf, findsOneWidget);
      await tester.enterText(tf, 'déboucher un évier');
      await tester.pump();

      // Tap ELI5
      await tester.tap(find.text('ELI5'));
      await tester.pump();
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('Rechercher'));
      await tester.pump();

      expect(submitted, isNotNull);
      expect(submitted, contains("Explique comme si j'avais 5 ans:"));

      // Ensure persistence of last template selection
      final provider2 = SearchProvider(prefs: prefs, testMode: true);
      expect(provider2.lastTemplate, 'eli5');
    });
  });
}
