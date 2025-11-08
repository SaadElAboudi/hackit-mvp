import 'package:flutter/material.dart';
import '../widgets/adaptive_widget.dart';
import 'responsive_config.dart';

/// A grid layout that adapts its columns and spacing based on screen size
class AdaptiveGrid extends AdaptiveWidget {
  final List<Widget> children;
  final double? spacing;
  final double? runSpacing;
  final EdgeInsets? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final Alignment alignment;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.spacing,
    this.runSpacing,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
    // Alignment.start is invalid; use topLeft as a sensible default.
    this.alignment = Alignment.topLeft,
  });

  @override
  Widget buildMobileLayout(BuildContext context) {
    return _buildGrid(
      context,
      crossAxisCount: ResponsiveConfig.mobileColumns,
      childAspectRatio: 1,
    );
  }

  @override
  Widget buildTabletLayout(BuildContext context) {
    return _buildGrid(
      context,
      crossAxisCount: ResponsiveConfig.tabletColumns,
      childAspectRatio: 1.2,
    );
  }

  @override
  Widget buildDesktopLayout(BuildContext context) {
    return _buildGrid(
      context,
      crossAxisCount: ResponsiveConfig.desktopColumns,
      childAspectRatio: 1.5,
    );
  }

  Widget _buildGrid(
    BuildContext context, {
    required int crossAxisCount,
    required double childAspectRatio,
  }) {
    return GridView.builder(
      padding: padding ?? ResponsiveConfig.getResponsiveInsets(context),
      shrinkWrap: shrinkWrap,
      physics: physics,
      controller: controller,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing ?? ResponsiveConfig.getSpacing('md'),
        mainAxisSpacing: runSpacing ?? ResponsiveConfig.getSpacing('md'),
        childAspectRatio: childAspectRatio,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

/// Extension for creating responsive grids with specific column arrangements
class AdaptiveGridLayout extends AdaptiveWidget {
  final List<Widget> children;
  final Map<String, int> columnConfig;
  final double spacing;
  final double runSpacing;
  final EdgeInsets? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final ScrollController? controller;

  const AdaptiveGridLayout({
    super.key,
    required this.children,
    this.columnConfig = const {
      'mobile': 1,
      'tablet': 2,
      'desktop': 3,
    },
    this.spacing = 16,
    this.runSpacing = 16,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
  });

  @override
  Widget buildMobileLayout(BuildContext context) {
    return _buildWrappedLayout(context, columnConfig['mobile'] ?? 1);
  }

  @override
  Widget buildTabletLayout(BuildContext context) {
    return _buildWrappedLayout(context, columnConfig['tablet'] ?? 2);
  }

  @override
  Widget buildDesktopLayout(BuildContext context) {
    return _buildWrappedLayout(context, columnConfig['desktop'] ?? 3);
  }

  Widget _buildWrappedLayout(BuildContext context, int columns) {
    return SingleChildScrollView(
      physics: physics,
      controller: controller,
      padding: padding,
      child: Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: children.map((child) {
          return SizedBox(
            width: (MediaQuery.of(context).size.width -
                    (spacing * (columns - 1))) /
                columns,
            child: child,
          );
        }).toList(),
      ),
    );
  }
}
