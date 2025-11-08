import 'package:flutter/material.dart';
import 'responsive_layout.dart';

/// Classe utilitaire qui fournit des styles et dimensions adaptatives
/// en fonction de la taille de l'écran.
class AdaptiveStyles {
  /// Retourne la largeur maximale du contenu en fonction de la taille de l'écran
  static double getContentMaxWidth(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return 1200;
    } else if (ResponsiveLayout.isTablet(context)) {
      return 768;
    }
    return MediaQuery.of(context).size.width;
  }

  /// Retourne le padding horizontal adaptatif
  static EdgeInsets getHorizontalPadding(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return const EdgeInsets.symmetric(horizontal: 48);
    } else if (ResponsiveLayout.isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 32);
    }
    return const EdgeInsets.symmetric(horizontal: 16);
  }

  /// Retourne le nombre de colonnes pour la grille en fonction de la taille de l'écran
  static int getGridColumns(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return 4;
    } else if (ResponsiveLayout.isTablet(context)) {
      return 3;
    }
    return 2;
  }

  /// Retourne la taille de la police adaptative
  static double getAdaptiveFontSize(
    BuildContext context,
    double mobileFontSize, {
    double? tabletFontSize,
    double? desktopFontSize,
  }) {
    if (ResponsiveLayout.isDesktop(context)) {
      return desktopFontSize ?? (mobileFontSize * 1.5);
    } else if (ResponsiveLayout.isTablet(context)) {
      return tabletFontSize ?? (mobileFontSize * 1.25);
    }
    return mobileFontSize;
  }

  /// Retourne les dimensions adaptatives pour les cartes vidéo
  static Size getVideoCardSize(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return const Size(320, 280);
    } else if (ResponsiveLayout.isTablet(context)) {
      return const Size(280, 240);
    }
    return const Size(160, 140);
  }
}