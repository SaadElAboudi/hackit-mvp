import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/search_provider.dart';
import 'providers/history_favorites_provider.dart';
import 'providers/lessons_provider.dart';
import 'services/cache_manager.dart';
import 'screens/home_screen.dart';
import 'screens/root_tabs.dart';
import 'screens/result_screen.dart';
import 'screens/history_screen.dart';
import 'screens/favorites_screen.dart';
import 'utils/page_transitions.dart';

final getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize shared preferences
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // Initialize cache manager
  final cacheManager = CacheManager(prefs);
  getIt.registerSingleton<CacheManager>(cacheManager);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final bool skipLessonsInit;
  const MyApp({super.key, this.skipLessonsInit = false});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(getIt<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (_) => HistoryFavoritesProvider(getIt<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (_) => LessonsProvider(prefs: getIt<SharedPreferences>())
          // Deferred initialization to avoid timers/network during widget build in tests
          ,
        ),
        ChangeNotifierProvider(
          create: (ctx) => SearchProvider(
            cacheManager: getIt<CacheManager>(),
            prefs: getIt<SharedPreferences>(),
            historyFavorites: ctx.read<HistoryFavoritesProvider>(),
          ),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          // Link legacy history/favorites with lessons after providers are ready.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              final hist = context.read<HistoryFavoritesProvider>();
              final lessons = context.read<LessonsProvider>();
              hist.linkLessons(lessons);
              // Initialize lessons after first frame unless explicitly skipped (tests)
              if (!skipLessonsInit) {
                lessons.initIfNeeded();
              }
            } catch (_) {}
          });
          return MaterialApp(
            title: 'Hackit MVP',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case '/':
                  return PageTransitions.fadeTransition(
                    page: const RootTabs(),
                    settings: settings,
                  );
                case '/history':
                  return PageTransitions.slideTransition(
                    page: const HistoryScreen(),
                    settings: settings,
                  );
                case '/favorites':
                  return PageTransitions.slideTransition(
                    page: const FavoritesScreen(),
                    settings: settings,
                  );
                case '/result':
                  return PageTransitions.slideTransition(
                    page: const ResultScreen(),
                    settings: settings,
                  );
                default:
                  return PageTransitions.fadeTransition(
                    page: const HomeScreen(),
                    settings: settings,
                  );
              }
            },
          );
        },
      ),
    );
  }
}
