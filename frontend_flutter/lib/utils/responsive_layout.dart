import 'package:flutter/material.dart';

/// ResponsiveLayout est une classe utilitaire qui aide à créer des layouts
/// adaptifs en fonction de la taille de l'écran.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  /// Crée un layout responsive avec différentes vues pour mobile, tablet et desktop.
  ///
  /// [mobile] : Layout pour les écrans mobiles (obligatoire)
  /// [tablet] : Layout pour les tablettes (optionnel, utilise mobile si non fourni)
  /// [desktop] : Layout pour les écrans larges (optionnel, utilise tablet si non fourni)
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  /// Points de rupture pour les différentes tailles d'écran
  static const double kTabletBreakpoint = 768;
  static const double kDesktopBreakpoint = 1024;

  /// Détermine si l'appareil est un mobile
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < kTabletBreakpoint;

  /// Détermine si l'appareil est une tablette
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= kTabletBreakpoint &&
      MediaQuery.of(context).size.width < kDesktopBreakpoint;

  /// Détermine si l'appareil est un desktop
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= kDesktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopBreakpoint) {
          return desktop ?? tablet ?? mobile;
        }
        if (constraints.maxWidth >= kTabletBreakpoint) {
          return tablet ?? mobile;
        }
        return mobile;
      },
    );
  }
}