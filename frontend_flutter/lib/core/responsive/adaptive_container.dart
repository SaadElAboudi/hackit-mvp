import 'package:flutter/material.dart';
import '../widgets/adaptive_widget.dart';
import 'responsive_config.dart';

/// A container widget that adapts its layout based on screen size
class AdaptiveContainer extends AdaptiveWidget {
  final Widget child;
  final Color? backgroundColor;
  final EdgeInsets? padding;
  final BoxDecoration? decoration;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final Alignment? alignment;

  const AdaptiveContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding,
    this.decoration,
    this.width,
    this.height,
    this.constraints,
    this.alignment,
  });

  @override
  Widget buildMobileLayout(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? ResponsiveConfig.getResponsiveInsets(context),
      decoration: decoration ??
          BoxDecoration(
            color: backgroundColor ?? Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
          ),
      constraints: constraints ??
          BoxConstraints(
            maxWidth: ResponsiveConfig.getContentMaxWidth(context),
          ),
      alignment: alignment,
      child: child,
    );
  }

  @override
  Widget buildTabletLayout(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? ResponsiveConfig.getResponsiveInsets(context),
      decoration: decoration ??
          BoxDecoration(
            color: backgroundColor ?? Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
      constraints: constraints ??
          BoxConstraints(
            maxWidth: ResponsiveConfig.getContentMaxWidth(context),
          ),
      alignment: alignment,
      child: child,
    );
  }

  @override
  Widget buildDesktopLayout(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? ResponsiveConfig.getResponsiveInsets(context),
      decoration: decoration ??
          BoxDecoration(
            color: backgroundColor ?? Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
      constraints: constraints ??
          BoxConstraints(
            maxWidth: ResponsiveConfig.getContentMaxWidth(context),
          ),
      alignment: alignment,
      child: child,
    );
  }
}
