import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hackit_mvp_flutter/providers/history_favorites_provider.dart';
import 'package:hackit_mvp_flutter/widgets/video_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoCard favorite toggle', () {
    testWidgets('toggles favorite state', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = HistoryFavoritesProvider(prefs);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VideoCard(
                title: 'Sample Video',
                videoUrl: 'https://example.com/v/123',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final favBtn = find.byKey(const Key('video_favorite_toggle'));
      expect(favBtn, findsOneWidget);
      expect(provider.favorites.length, 0);

      // Add to favorites
      await tester.tap(favBtn);
      await tester.pumpAndSettle();
      expect(provider.favorites.length, 1);
      expect(provider.isFavorite('https://example.com/v/123'), isTrue);

      // Remove from favorites
      await tester.tap(favBtn);
      await tester.pumpAndSettle();
      expect(provider.favorites.length, 0);
      expect(provider.isFavorite('https://example.com/v/123'), isFalse);
    });
  });
}
