import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'providers/google_auth_provider.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/search_provider.dart';
import 'providers/history_favorites_provider.dart';
import 'providers/lessons_provider.dart';
import 'services/cache_manager.dart';
// import 'screens/home_screen.dart';
import 'screens/root_tabs.dart';
import 'screens/result_screen.dart';
// import 'screens/history_screen.dart';
// import 'screens/favorites_screen.dart';
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

class MyApp extends StatefulWidget {
  final bool skipLessonsInit;
  const MyApp({super.key, this.skipLessonsInit = false});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // bool _guestMode = false; // Removed unused field

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GoogleAuthProvider()),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
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
      child: Consumer<GoogleAuthProvider>(
        builder: (context, googleAuth, _) {
          if (googleAuth.user == null) {
            return MaterialApp(
              title: 'Hackit MVP',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              home: LoginScreen(),
            );
          }
          return Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  final hist = context.read<HistoryFavoritesProvider>();
                  final lessons = context.read<LessonsProvider>();
                  // Ajoute l'interceptor d'auth Google sur l'ApiService
                  lessons.service.api.addAuthInterceptor(
                      Provider.of<GoogleAuthProvider>(context, listen: false));
                  hist.linkLessons(lessons);
                  if (!widget.skipLessonsInit) {
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
                onGenerateRoute: (settings) {
                  switch (settings.name) {
                    case '/':
                      return PageTransitions.fadeTransition(
                        page: const RootTabs(),
                        settings: settings,
                      );
                    case '/lessons':
                      return PageTransitions.slideTransition(
                        page: const RootTabs(),
                        settings: settings,
                      );
                    case '/favorites':
                      return PageTransitions.slideTransition(
                        page: const RootTabs(),
                        settings: settings,
                      );
                    case '/history':
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
          );
        },
      ),
    );
  }
}
