import 'package:flutter/material.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';

class UserBubble extends StatelessWidget {
  final String text;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final bool disabled;
  const UserBubble({
    super.key,
    required this.text,
    this.onEdit,
    this.onRegenerate,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    final bubble = Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(18),
      color: scheme.primary.withOpacity(0.85), // Couleur plus foncée
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18)
              .copyWith(bottomRight: const Radius.circular(6)),
          border: Border.all(
            color: scheme.primary.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AdaptiveSpacing.large,
            vertical: AdaptiveSpacing.medium,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: SizeConfig.adaptiveFontSize(15),
              height: 1.32,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: SizeConfig.screenWidth * 0.95,
        ),
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(18),
          color: scheme.surfaceContainerHighest
              .withOpacity(0.90), // Couleur plus foncée
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18)
                  .copyWith(bottomLeft: const Radius.circular(6)),
              border: Border.all(
                color: scheme.surfaceContainerHighest.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AdaptiveSpacing.large,
                AdaptiveSpacing.medium,
                AdaptiveSpacing.large,
                AdaptiveSpacing.medium + 2,
              ),
              child: DefaultTextStyle(
                style: TextStyle(color: Colors.white),
                child: child,
              ),
            ),
          ),
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
