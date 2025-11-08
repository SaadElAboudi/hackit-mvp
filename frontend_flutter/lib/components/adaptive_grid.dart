import 'package:flutter/material.dart';
import '../utils/responsive_layout.dart';
import '../utils/adaptive_styles.dart';

/// Un widget de grille qui s'adapte automatiquement à la taille de l'écran
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final EdgeInsets? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final ScrollController? controller;

  /// Crée une grille adaptive
  /// 
  /// [children] : Les widgets à afficher dans la grille
  /// [spacing] : L'espacement entre les éléments (horizontal et vertical)
  /// [padding] : Le padding autour de la grille
  /// [physics] : La physique du défilement
  /// [shrinkWrap] : Si true, la grille prend la taille de son contenu
  /// [controller] : Le contrôleur de défilement optionnel
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.spacing = 16,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.controller,
  });

  int _getColumnCount(BuildContext context) {
    return AdaptiveStyles.getGridColumns(context);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = _getColumnCount(context);
        final itemWidth = (constraints.maxWidth - (spacing * (columnCount - 1))) / columnCount;

        return GridView.builder(
          padding: padding,
          physics: physics,
          shrinkWrap: shrinkWrap,
          controller: controller,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: itemWidth / (itemWidth * 0.8), // Aspect ratio 4:3
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}