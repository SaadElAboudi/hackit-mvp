import 'package:flutter/material.dart';

/// Small tactile button with subtle neumorphic depth.
class NeumorphicActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const NeumorphicActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final base = isDark
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.62)
        : scheme.surface.withValues(alpha: 0.92);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.40)
                    : Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(3, 4),
              ),
              BoxShadow(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.88),
                blurRadius: 10,
                offset: const Offset(-3, -4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final text = Text(
                label,
                maxLines: 1,
                overflow: constraints.hasBoundedWidth
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              );
              return Row(
                mainAxisSize: constraints.hasBoundedWidth
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                  ],
                  constraints.hasBoundedWidth ? Flexible(child: text) : text,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
