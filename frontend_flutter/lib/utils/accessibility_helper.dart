// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class AccessibilityHelper {
  static void announceForAccessibility(BuildContext context, String message) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  static Widget addSemantics({
    required Widget child,
    required String label,
    String? hint,
    bool isButton = false,
    VoidCallback? onTap,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      button: isButton,
      enabled: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: child,
      ),
    );
  }

  static Widget addScreenReader({
    required Widget child,
    required String announcement,
  }) {
    return Semantics(
      label: announcement,
      child: child,
    );
  }

  static const double minTouchTarget = 48.0;

  static Widget enlargeTouchTarget({
    required Widget child,
    double size = minTouchTarget,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: child),
    );
  }
}
