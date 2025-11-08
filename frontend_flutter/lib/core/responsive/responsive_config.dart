import 'package:flutter/material.dart';

/// Configuration class for responsive design breakpoints and dimensions
class ResponsiveConfig {
  // Screen size breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 768;
  static const double desktopBreakpoint = 1024;
  static const double largeDesktopBreakpoint = 1440;

  // Content width constraints
  static const double maxMobileContentWidth = 600;
  static const double maxTabletContentWidth = 768;
  static const double maxDesktopContentWidth = 1200;

  // Grid columns
  static const int mobileColumns = 4;
  static const int tabletColumns = 8;
  static const int desktopColumns = 12;

  // Font sizes
  static const Map<String, double> fontSizes = {
    'xs': 12,
    'sm': 14,
    'md': 16,
    'lg': 18,
    'xl': 20,
    'xxl': 24,
    'display': 32,
  };

  // Spacing scale
  static const Map<String, double> spacing = {
    'xxs': 4,
    'xs': 8,
    'sm': 12,
    'md': 16,
    'lg': 24,
    'xl': 32,
    'xxl': 48,
  };

  /// Get the appropriate number of grid columns based on screen width
  static int getGridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopBreakpoint) return desktopColumns;
    if (width >= tabletBreakpoint) return tabletColumns;
    return mobileColumns;
  }

  /// Get content max width based on screen size
  static double getContentMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopBreakpoint) return maxDesktopContentWidth;
    if (width >= tabletBreakpoint) return maxTabletContentWidth;
    return maxMobileContentWidth;
  }

  /// Get responsive font size with optional scale factor
  static double getFontSize(String size, [double scale = 1.0]) {
    return (fontSizes[size] ?? fontSizes['md']!) * scale;
  }

  /// Get spacing value
  static double getSpacing(String size) {
    return spacing[size] ?? spacing['md']!;
  }

  /// Get responsive edge insets
  static EdgeInsets getResponsiveInsets(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopBreakpoint) {
      return EdgeInsets.all(spacing['xl']!);
    }
    if (width >= tabletBreakpoint) {
      return EdgeInsets.all(spacing['lg']!);
    }
    return EdgeInsets.all(spacing['md']!);
  }
}