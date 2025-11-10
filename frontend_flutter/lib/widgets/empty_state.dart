import 'package:flutter/material.dart';
import '../core/responsive/adaptive_spacing.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title; // Keep exact text for tests (e.g., "Aucun historique")
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AdaptiveSpacing.large),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(AdaptiveSpacing.medium),
                  child: Icon(icon, size: 42, color: scheme.primary),
                ),
              ),
              SizedBox(height: AdaptiveSpacing.medium),
              // Title should keep the exact string for tests (e.g., "Aucun favori")
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: AdaptiveSpacing.small),
                Opacity(
                  opacity: 0.8,
                  child: Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: AdaptiveSpacing.medium),
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(actionLabel!),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}
