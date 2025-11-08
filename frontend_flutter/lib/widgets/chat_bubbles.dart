import 'package:flutter/material.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';

class UserBubble extends StatelessWidget {
  final String text;
  const UserBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: SizeConfig.screenWidth * 0.85,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: const Radius.circular(4),
            ),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AdaptiveSpacing.medium,
              vertical: AdaptiveSpacing.small + 2,
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: SizeConfig.adaptiveFontSize(14),
                height: 1.35,
              ),
            ),
          ),
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
        child: DecoratedBox(
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
          child: Padding(
            padding: EdgeInsets.all(AdaptiveSpacing.small),
            child: child,
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
