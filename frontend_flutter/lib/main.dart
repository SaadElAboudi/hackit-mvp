import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/room_provider.dart';
import 'services/cache_manager.dart';
import 'services/project_service.dart';
import 'services/api/api_service.dart';
import 'screens/root_tabs.dart';
import 'screens/onboarding_screen.dart';

final getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  final cacheManager = CacheManager(prefs);
  getIt.registerSingleton<CacheManager>(cacheManager);

  await ProjectService.init();

  // Warm up backend (Render free tier cold start)
  unawaited(ApiService.create().pingHealth(
    timeout: const Duration(seconds: 90),
  ));

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => RoomProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Hackit',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: ProjectService.isOnboarded
                ? const RootTabs()
                : _OnboardingWrapper(),
          );
        },
      ),
    );
  }
}

/// Wraps onboarding and replaces itself with RootTabs on completion.
class _OnboardingWrapper extends StatefulWidget {
  @override
  State<_OnboardingWrapper> createState() => _OnboardingWrapperState();
}

class _OnboardingWrapperState extends State<_OnboardingWrapper> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) return const RootTabs();
    return OnboardingScreen(
      onComplete: () => setState(() => _done = true),
    );
  }
}

