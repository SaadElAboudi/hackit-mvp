import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';

@singleton
class ThemeService {
  static const String _themePreferenceKey = 'theme_mode';
  static const String _customThemeKey = 'custom_theme';

  final _themeController = BehaviorSubject<ThemeData>();
  final _themeModeController = BehaviorSubject<ThemeMode>();
  final SharedPreferences _preferences;

  Stream<ThemeData> get theme => _themeController.stream;
  Stream<ThemeMode> get themeMode => _themeModeController.stream;

  ThemeService(this._preferences) {
    _init();
  }

  Future<void> _init() async {
    // Charger le mode de thème sauvegardé
    final savedThemeMode = _preferences.getString(_themePreferenceKey);
    final initialThemeMode = _parseThemeMode(savedThemeMode);
    _themeModeController.add(initialThemeMode);

    // Initialiser le thème
    await _updateTheme(initialThemeMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _preferences.setString(_themePreferenceKey, mode.toString());
    _themeModeController.add(mode);
    await _updateTheme(mode);
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    // Récupérer les couleurs dynamiques du système
    final ColorScheme? dynamicColors = await DynamicColorPlugin.getColorScheme();
    
    // Créer le thème en fonction du mode et des couleurs disponibles
    final theme = _createTheme(mode, dynamicColors);
    _themeController.add(theme);
  }

  ThemeData _createTheme(ThemeMode mode, ColorScheme? dynamicColors) {
    // Charger le thème personnalisé sauvegardé
    final savedCustomTheme = _preferences.getString(_customThemeKey);
    final CustomThemeData? customTheme = savedCustomTheme != null
        ? CustomThemeData.fromJson(savedCustomTheme)
        : null;

    // Base du thème
    var theme = mode == ThemeMode.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    // Appliquer les couleurs dynamiques si disponibles
    if (dynamicColors != null) {
      theme = theme.copyWith(
        colorScheme: dynamicColors,
      );
    }

    // Appliquer le thème personnalisé si disponible
    if (customTheme != null) {
      theme = theme.copyWith(
        primaryColor: customTheme.primaryColor,
        colorScheme: theme.colorScheme.copyWith(
          primary: customTheme.primaryColor,
          secondary: customTheme.accentColor,
        ),
      );
    }

    // Appliquer des personnalisations supplémentaires
    return theme.copyWith(
      // Personnalisation des composants
      appBarTheme: AppBarTheme(
        elevation: 0,
        systemOverlayStyle: mode == ThemeMode.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Future<void> saveCustomTheme(CustomThemeData customTheme) async {
    await _preferences.setString(
      _customThemeKey,
      customTheme.toJson(),
    );
    await _updateTheme(_themeModeController.value);
  }

  ThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case 'ThemeMode.light':
        return ThemeMode.light;
      case 'ThemeMode.dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void dispose() {
    _themeController.close();
    _themeModeController.close();
  }
}

class CustomThemeData {
  final Color primaryColor;
  final Color accentColor;
  final Color? backgroundColor;
  final double? borderRadius;
  final double? elevation;

  CustomThemeData({
    required this.primaryColor,
    required this.accentColor,
    this.backgroundColor,
    this.borderRadius,
    this.elevation,
  });

  factory CustomThemeData.fromJson(String json) {
    final map = jsonDecode(json);
    return CustomThemeData(
      primaryColor: Color(map['primaryColor']),
      accentColor: Color(map['accentColor']),
      backgroundColor: map['backgroundColor'] != null
          ? Color(map['backgroundColor'])
          : null,
      borderRadius: map['borderRadius']?.toDouble(),
      elevation: map['elevation']?.toDouble(),
    );
  }

  String toJson() {
    return jsonEncode({
      'primaryColor': primaryColor.value,
      'accentColor': accentColor.value,
      'backgroundColor': backgroundColor?.value,
      'borderRadius': borderRadius,
      'elevation': elevation,
    });
  }
}