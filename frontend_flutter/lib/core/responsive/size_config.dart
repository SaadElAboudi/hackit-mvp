import 'package:flutter/material.dart';

class SizeConfig {
  static bool _initialized = false;
  static bool get initialized => _initialized;
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double blockSizeHorizontal;
  static late double blockSizeVertical;
  static late double _safeAreaHorizontal;
  static late double _safeAreaVertical;
  static late double safeBlockHorizontal;
  static late double safeBlockVertical;
  static late double devicePixelRatio;
  static late double
      textScalerFactor; // renamed from deprecated textScaleFactor

  static void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    blockSizeHorizontal = screenWidth / 100;
    blockSizeVertical = screenHeight / 100;

    _safeAreaHorizontal =
        _mediaQueryData.padding.left + _mediaQueryData.padding.right;
    _safeAreaVertical =
        _mediaQueryData.padding.top + _mediaQueryData.padding.bottom;
    safeBlockHorizontal = (screenWidth - _safeAreaHorizontal) / 100;
    safeBlockVertical = (screenHeight - _safeAreaVertical) / 100;

    devicePixelRatio = _mediaQueryData.devicePixelRatio;
    textScalerFactor = _mediaQueryData.textScaler.scale(1.0);
    _initialized = true;
  }

  static void ensureInitialized(BuildContext context) {
    if (!_initialized) {
      init(context);
    }
  }

  static double getProportionateScreenHeight(double inputHeight) {
    return (inputHeight / 812.0) * screenHeight;
  }

  static double getProportionateScreenWidth(double inputWidth) {
    return (inputWidth / 375.0) * screenWidth;
  }

  // Base scaling using width with clamp to avoid extreme sizes
  static double _scaleWidth() => screenWidth / 375.0;

  static double _clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static double adaptiveSize(double size,
      {double minScale = 0.85, double maxScale = 1.25}) {
    final factor = _clamp(_scaleWidth(), minScale, maxScale);
    return size * factor;
  }

  static double adaptiveFontSize(double size,
      {double minScale = 0.90, double maxScale = 1.30}) {
    final factor = _clamp(_scaleWidth(), minScale, maxScale);
    // Respect user's textScaleFactor but clamp the effect to avoid overflow
    final textFactor = _clamp(textScalerFactor, 0.9, 1.3);
    return size * factor * textFactor;
  }
}
