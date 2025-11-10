import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hackit_mvp_flutter/providers/history_favorites_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HistoryFavoritesProvider', () {
    late HistoryFavoritesProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      provider = HistoryFavoritesProvider(prefs);
    });

    test('adds history and prunes beyond 50', () async {
      for (var i = 0; i < 55; i++) {
        await provider.addHistory(query: 'q$i', title: 't$i');
      }
      expect(provider.history.length <= 50, true);
      // Most recent should be last inserted
      expect(provider.history.first.query, 'q54');
    });

    test('toggle favorites add/remove', () async {
      await provider.toggleFavorite(videoId: 'vid1', title: 'Video 1');
      expect(provider.isFavorite('vid1'), true);
      await provider.toggleFavorite(videoId: 'vid1', title: 'Video 1');
      expect(provider.isFavorite('vid1'), false);
    });
  });
}
