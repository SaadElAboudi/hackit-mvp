import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hackit_mvp_flutter/screens/history_screen.dart';
import 'package:hackit_mvp_flutter/screens/favorites_screen.dart';
import 'package:hackit_mvp_flutter/providers/history_favorites_provider.dart';
import 'package:hackit_mvp_flutter/providers/search_provider.dart';
import 'package:hackit_mvp_flutter/providers/lessons_provider.dart';
import 'package:hackit_mvp_flutter/core/responsive/size_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper widget to ensure SizeConfig is initialized for adaptive spacing.
  Widget wrapWithInit(Widget child) => MaterialApp(
        home: Builder(
          builder: (context) {
            // Initialize responsive metrics once.
            try {
              // ignore: unnecessary_statements
              // Ensure no exception if already initialized.
              // We call ensureInitialized to avoid late fields errors.
              // Using dynamic call to avoid direct dependency in case of refactor.
              // However import path is stable.
              // ignore: avoid_dynamic_calls
              SizeConfig.ensureInitialized(
                  context); // Ensure SizeConfig is initialized
            } catch (_) {}
            return child;
          },
        ),
      );

  group('History & Favorites screens', () {
    late SharedPreferences prefs;
    late HistoryFavoritesProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      provider = HistoryFavoritesProvider(prefs);
    });

    testWidgets('HistoryScreen renders entries and replay button enabled',
        (tester) async {
      // Seed two history entries.
      await provider.addHistory(
          query: 'video cats', title: 'Les chats marrants');
      await provider.addHistory(query: 'video dogs', title: 'Les chiens cool');

      final searchProvider = SearchProvider(
        prefs: prefs,
        historyFavorites: provider,
        testMode: true,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<HistoryFavoritesProvider>.value(
                value: provider),
            ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
            // Provide LessonsProvider (no init) to satisfy HistoryScreen Consumer3
            ChangeNotifierProvider(
              create: (_) => LessonsProvider(prefs: prefs),
            ),
          ],
          child: wrapWithInit(const HistoryScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Les chats marrants'), findsOneWidget);
      expect(find.text('Les chiens cool'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    });

    testWidgets('FavoritesScreen shows favorites and allows removal',
        (tester) async {
      // Seed favorites via toggleFavorite.
      await provider.toggleFavorite(
        videoId: 'vid_1',
        title: 'Vidéo 1',
        channel: 'Chaine A',
        videoUrl: 'https://example.com/v1',
      );
      await provider.toggleFavorite(
        videoId: 'vid_2',
        title: 'Vidéo 2',
        channel: 'Chaine B',
        videoUrl: 'https://example.com/v2',
      );

      expect(provider.favorites.length, 2);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<HistoryFavoritesProvider>.value(
                value: provider),
            ChangeNotifierProvider(
              create: (_) => LessonsProvider(prefs: prefs),
            ),
          ],
          child: wrapWithInit(const FavoritesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vidéo 1'), findsOneWidget);
      expect(find.text('Vidéo 2'), findsOneWidget);

      // Remove first favorite by tapping its close icon.
      final removeButtons = find.byIcon(Icons.close_rounded);
      expect(removeButtons, findsNWidgets(2));
      await tester.tap(removeButtons.first);
      await tester.pump();

      // Provider should now have 1 favorite.
      expect(provider.favorites.length, 1);
    });
  });
}
