import 'package:flutter/material.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  final Color accentInfo;
  final Color accentWarning;
  final Color accentDanger;
  final Color accentSuccess;
  final Color badgeBg;
  final Color badgeText;

  const AppPalette({
    required this.accentInfo,
    required this.accentWarning,
    required this.accentDanger,
    required this.accentSuccess,
    required this.badgeBg,
    required this.badgeText,
  });

  @override
  AppPalette copyWith({
    Color? accentInfo,
    Color? accentWarning,
    Color? accentDanger,
    Color? accentSuccess,
    Color? badgeBg,
    Color? badgeText,
  }) {
    return AppPalette(
      accentInfo: accentInfo ?? this.accentInfo,
      accentWarning: accentWarning ?? this.accentWarning,
      accentDanger: accentDanger ?? this.accentDanger,
      accentSuccess: accentSuccess ?? this.accentSuccess,
      badgeBg: badgeBg ?? this.badgeBg,
      badgeText: badgeText ?? this.badgeText,
    );
  }

  @override
  ThemeExtension<AppPalette> lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      accentInfo: Color.lerp(accentInfo, other.accentInfo, t)!,
      accentWarning: Color.lerp(accentWarning, other.accentWarning, t)!,
      accentDanger: Color.lerp(accentDanger, other.accentDanger, t)!,
      accentSuccess: Color.lerp(accentSuccess, other.accentSuccess, t)!,
      badgeBg: Color.lerp(badgeBg, other.badgeBg, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
    );
  }

  static AppPalette fromScheme(ColorScheme scheme) {
    return AppPalette(
      accentInfo: scheme.primary,
      accentWarning: scheme.tertiaryContainer,
      accentDanger: scheme.error,
      accentSuccess: scheme.secondary,
      badgeBg: scheme.errorContainer.withValues(alpha: 0.85),
      badgeText: scheme.onErrorContainer,
    );
  }
}
