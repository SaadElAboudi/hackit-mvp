import 'package:flutter/material.dart';
import 'app_extensions.dart';

class AppTheme {
  static ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A56DB),
      brightness: brightness,
    );

    final isDark = brightness == Brightness.dark;

    final baseText = isDark
        ? Typography.material2021().white
        : Typography.material2021().black;

    // Layered surfaces for depth
    // surfaceTint reserved for future surfaces
    // final surfaceTint = scheme.primary;
    // Elevated overlay reserved for future containers (currently unused)
    // final elevatedOverlay = scheme.surface.withValues(alpha: isDark ? 0.3 : 0.6);
    final glassOverlay = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.4);

    // Base component radius scale for a softer, consistent aesthetic
    const baseRadius = 16.0;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: baseText
          .apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          )
          .copyWith(
            headlineMedium: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            titleLarge: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: const TextStyle(height: 1.3),
            bodyMedium: const TextStyle(height: 1.35),
          ),
      // Remove initial placeholder cardTheme; a configured cardTheme is provided later.
      // Custom card styling extension through theme extensions (kept simple to avoid type mismatch)
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 16,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassOverlay,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(baseRadius + 2),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(baseRadius + 2),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(baseRadius + 2),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(baseRadius),
          ),
          elevation: 2,
          shadowColor: scheme.primary.withValues(alpha: 0.3),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return scheme.primaryContainer.withValues(alpha: 0.25);
            }
            if (states.contains(WidgetState.hovered)) {
              return scheme.primaryContainer.withValues(alpha: 0.15);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(
              color: scheme.primary.withValues(alpha: 0.7), width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(baseRadius)),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return scheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return scheme.primary.withValues(alpha: 0.20);
            }
            return null;
          }),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(baseRadius),
        ),
        tileColor: scheme.surfaceContainerHighest
            .withValues(alpha: isDark ? 0.25 : 0.6),
      ),
      splashFactory: InkSparkle.splashFactory,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface.withValues(alpha: 0.92),
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.primary);
          }
          return IconThemeData(color: scheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return TextStyle(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
      // withOpacity deprecated; prefer withValues for precise alpha handling
      hoverColor: scheme.primary.withValues(alpha: 0.10),
      splashColor: scheme.primary.withValues(alpha: 0.18),
      highlightColor: scheme.primary.withValues(alpha: 0.12),
      // Unified Card styling
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: scheme.primary.withValues(alpha: 0.18),
        surfaceTintColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(baseRadius + 4),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(8),
        clipBehavior: Clip.antiAlias,
      ),
      extensions: [AppPalette.fromScheme(scheme)],
    );
  }

  static final ThemeData lightTheme = _buildTheme(Brightness.light);
  static final ThemeData darkTheme = _buildTheme(Brightness.dark);
}
