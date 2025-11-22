import 'package:flutter/material.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';

class UserBubble extends StatelessWidget {
  final String text;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final bool disabled;
  final Color textColor;
  const UserBubble({
    super.key,
    required this.text,
    this.onEdit,
    this.onRegenerate,
    this.disabled = false,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    // ...existing code...
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: SizeConfig.adaptiveFontSize(15),
          height: 1.32,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
      ),
    );

    final actions = (onEdit != null || onRegenerate != null)
        ? Padding(
            padding: EdgeInsets.only(top: AdaptiveSpacing.tiny),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onRegenerate != null)
                  Tooltip(
                    message: 'Relancer',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: disabled ? null : onRegenerate,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                if (onEdit != null)
                  Tooltip(
                    message: 'Modifier',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: disabled ? null : onEdit,
                      icon: const Icon(Icons.edit_rounded),
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: SizeConfig.screenWidth * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            bubble,
            actions,
          ],
        ),
      ),
    );
  }
}

class AssistantContainer extends StatelessWidget {
  final Widget child;
  const AssistantContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    // ...existing code...
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black),
          child: child,
        ),
      ),
    );
  }
}

class LoadingBubbles extends StatelessWidget {
  const LoadingBubbles({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    Widget skeleton({double height = 18, double widthFactor = 1}) => Container(
          width: SizeConfig.screenWidth * 0.6 * widthFactor,
          height: height,
          margin: EdgeInsets.only(bottom: AdaptiveSpacing.tiny + 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(child: skeleton(widthFactor: 0.7)),
          ],
        ),
        SizedBox(height: AdaptiveSpacing.small),
        Container(
          padding: EdgeInsets.all(AdaptiveSpacing.small),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomLeft: const Radius.circular(4),
            ),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              skeleton(widthFactor: 0.35),
              skeleton(),
              skeleton(widthFactor: 0.9),
              skeleton(widthFactor: 0.8),
              skeleton(widthFactor: 0.6),
            ],
          ),
        )
      ],
    );
  }
}
