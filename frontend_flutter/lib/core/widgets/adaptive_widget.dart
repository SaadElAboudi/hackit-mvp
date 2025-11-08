import 'package:flutter/material.dart';
import '../responsive/responsive_layout.dart';
import '../responsive/size_config.dart';

/// Base class for creating adaptive widgets that respond to different screen sizes
abstract class AdaptiveWidget extends StatelessWidget {
  const AdaptiveWidget({super.key});

  /// Build the mobile layout
  Widget buildMobileLayout(BuildContext context);

  /// Build the tablet layout
  Widget buildTabletLayout(BuildContext context) => buildMobileLayout(context);

  /// Build the desktop layout
  Widget buildDesktopLayout(BuildContext context) => buildTabletLayout(context);

  @override
  Widget build(BuildContext context) {
    // Initialize size configuration
    SizeConfig.init(context);

    // Return appropriate layout based on screen size
    if (ResponsiveLayout.isDesktop(context)) {
      return buildDesktopLayout(context);
    }
    
    if (ResponsiveLayout.isTablet(context)) {
      return buildTabletLayout(context);
    }
    
    return buildMobileLayout(context);
  }

  /// Helper method to get content max width based on screen size
  double getContentMaxWidth(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return 1200;
    }
    if (ResponsiveLayout.isTablet(context)) {
      return 768;
    }
    return MediaQuery.of(context).size.width;
  }

  /// Helper method to get adaptive padding
  EdgeInsets getAdaptivePadding(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return const EdgeInsets.all(32.0);
    }
    if (ResponsiveLayout.isTablet(context)) {
      return const EdgeInsets.all(24.0);
    }
    return const EdgeInsets.all(16.0);
  }

  /// Helper method to get adaptive font size
  double getAdaptiveFontSize(BuildContext context, double baseFontSize) {
    if (ResponsiveLayout.isDesktop(context)) {
      return baseFontSize * 1.25;
    }
    if (ResponsiveLayout.isTablet(context)) {
      return baseFontSize * 1.15;
    }
    return baseFontSize;
  }

  /// Helper method to get adaptive icon size
  double getAdaptiveIconSize(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return 32.0;
    }
    if (ResponsiveLayout.isTablet(context)) {
      return 28.0;
    }
    return 24.0;
  }
}