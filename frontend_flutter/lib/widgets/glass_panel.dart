import 'dart:ui';

import 'package:flutter/material.dart';

/// Reusable frosted-glass container with optional blur.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final Color? tint;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 14,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = tint ??
        (isDark
            ? scheme.surface.withValues(alpha: 0.36)
            : Colors.white.withValues(alpha: 0.68));

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
