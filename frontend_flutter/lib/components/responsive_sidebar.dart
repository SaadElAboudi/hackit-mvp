import 'package:flutter/material.dart';
import '../utils/responsive_layout.dart';
import '../utils/adaptive_styles.dart';

/// Un widget de barre latérale responsive qui peut se réduire ou s'étendre
class ResponsiveSidebar extends StatelessWidget {
  final List<Widget> children;
  final String title;
  final bool isExpanded;
  final VoidCallback? onToggle;
  final double width;
  final Color? backgroundColor;
  final Widget? footer;

  /// Crée une barre latérale responsive
  /// 
  /// [children] : Le contenu de la barre latérale
  /// [title] : Le titre de la barre latérale
  /// [isExpanded] : Si la barre latérale est étendue
  /// [onToggle] : Callback appelé lors du toggle de la barre
  /// [width] : Largeur de la barre latérale
  /// [backgroundColor] : Couleur de fond
  /// [footer] : Widget optionnel affiché en bas de la barre
  const ResponsiveSidebar({
    super.key,
    required this.children,
    required this.title,
    this.isExpanded = true,
    this.onToggle,
    this.width = 300,
    this.backgroundColor,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    // Sur mobile, on affiche un drawer
    if (ResponsiveLayout.isMobile(context)) {
      return Drawer(
        child: _buildContent(context),
      );
    }

    // Sur tablette/desktop, on affiche une barre latérale fixe
    return Container(
      width: isExpanded ? width : 60,
      decoration: BoxDecoration(
        color: backgroundColor ?? Theme.of(context).cardColor,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 16 : 8,
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: isExpanded
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: children,
            ),
          ),
        ),
        if (footer != null) footer!,
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          if (isExpanded) ...[
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: AdaptiveStyles.getAdaptiveFontSize(context, 18),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          if (onToggle != null)
            IconButton(
              icon: Icon(
                isExpanded ? Icons.chevron_left : Icons.chevron_right,
              ),
              onPressed: onToggle,
            ),
        ],
      ),
    );
  }
}