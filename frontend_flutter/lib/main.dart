import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/search_provider.dart';
import 'providers/history_favorites_provider.dart';
import 'providers/lessons_provider.dart';
import 'providers/action_task_provider.dart';
import 'providers/plan_feedback_provider.dart';
import 'providers/project_provider.dart';
import 'providers/collab_provider.dart';
import 'providers/room_provider.dart';
import 'services/cache_manager.dart';
import 'services/project_service.dart';
import 'services/api/api_service.dart';
import 'screens/root_tabs.dart';
import 'screens/result_screen.dart';
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

  // Resolve and persist the stable per-device userId used by ProjectService.
  // This ensures a consistent identity is ready before any collab call is made.
  await ProjectService.init();

  // Wake up the Render backend immediately (fire & forget).
  // Render free tier sleeps after 15 min of inactivity; cold start takes 30-60s.
  // By pinging now, the server is warm by the time the user sends their first message.
  unawaited(ApiService.create().pingHealth(
    timeout: const Duration(seconds: 90),
  ));

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  final bool skipLessonsInit;
  const MyApp({super.key, this.skipLessonsInit = false});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => CollabProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => RoomProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProjectProvider(getIt<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (_) => ActionTaskProvider(getIt<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (_) => PlanFeedbackProvider(getIt<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (_) => HistoryFavoritesProvider(getIt<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (_) => LessonsProvider(prefs: getIt<SharedPreferences>()),
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              final hist = context.read<HistoryFavoritesProvider>();
              final lessons = context.read<LessonsProvider>();
              hist.linkLessons(lessons);
              if (!(context
                      .findAncestorWidgetOfExactType<MyApp>()
                      ?.skipLessonsInit ??
                  false)) {
                lessons.initIfNeeded();
              }
            } catch (_) {}
          });
          return MaterialApp(
            title: 'Hackit MVP',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            initialRoute: '/',
            home: const RootTabs(),
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case '/':
                  return PageTransitions.fadeTransition(
                    page: const RootTabs(),
                    settings: settings,
                  );
                case '/lessons':
                case '/favorites':
                case '/history':
                case '/library':
                  return PageTransitions.slideTransition(
                    page: const RootTabs(),
                    settings: settings,
                  );
                case '/result':
                  return PageTransitions.slideTransition(
                    page: const ResultScreen(),
                    settings: settings,
                  );
                default:
                  return PageTransitions.fadeTransition(
                    page: const RootTabs(),
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
