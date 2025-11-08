import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hackit_mvp_flutter/providers/search_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Draft persistence', () {
    test('draft saved and restored across provider instances', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final p1 = SearchProvider(prefs: prefs, testMode: true);
      expect(p1.draftText, isNull);
      p1.setDraft('Bonjour');
      expect(p1.draftText, 'Bonjour');

      final p2 = SearchProvider(prefs: prefs, testMode: true);
      expect(p2.draftText, 'Bonjour');
      expect(p2.draftRestored, isTrue);
      p2.consumeDraftRestoredFlag();
      expect(p2.draftRestored, isFalse);
      p2.clearDraft();
      final p3 = SearchProvider(prefs: prefs, testMode: true);
      expect(p3.draftText, isNull);
    });
  });
}
