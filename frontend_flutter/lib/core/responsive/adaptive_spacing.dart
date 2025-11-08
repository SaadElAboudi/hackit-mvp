import 'package:flutter/material.dart';
import 'size_config.dart';

class AdaptiveSpacing {
  // Use getters so values adapt on each build after SizeConfig.init()
  static double get tiny => SizeConfig.adaptiveSize(4);
  static double get small => SizeConfig.adaptiveSize(8);
  static double get medium => SizeConfig.adaptiveSize(16);
  static double get large => SizeConfig.adaptiveSize(24);
  static double get extraLarge => SizeConfig.adaptiveSize(32);
  
  static EdgeInsets get screenPadding {
    if (SizeConfig.screenWidth >= 1024) {
      return EdgeInsets.symmetric(
        horizontal: SizeConfig.adaptiveSize(64),
        vertical: SizeConfig.adaptiveSize(32),
      );
    }
    if (SizeConfig.screenWidth >= 768) {
      return EdgeInsets.symmetric(
        horizontal: SizeConfig.adaptiveSize(32),
        vertical: SizeConfig.adaptiveSize(24),
      );
    }
    return EdgeInsets.symmetric(
      horizontal: SizeConfig.adaptiveSize(16),
      vertical: SizeConfig.adaptiveSize(16),
    );
  }

  static double get maxContentWidth {
    if (SizeConfig.screenWidth >= 1024) {
      return 1200;
    }
    if (SizeConfig.screenWidth >= 768) {
      return 900;
    }
    return SizeConfig.screenWidth - (SizeConfig.adaptiveSize(16) * 2);
  }
}