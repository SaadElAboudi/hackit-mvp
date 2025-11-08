import 'package:flutter/material.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';

class SummaryView extends StatelessWidget {
  final String title;
  final List<String> steps;
  const SummaryView({super.key, required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AdaptiveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.article_rounded, color: scheme.primary),
                SizedBox(width: AdaptiveSpacing.small),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: SizeConfig.adaptiveFontSize(20),
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AdaptiveSpacing.medium),
            if (steps.isNotEmpty) ...[
              Text(
                'Étapes',
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(16),
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: AdaptiveSpacing.small),
              ...steps.asMap().entries.map((entry) => Padding(
                    padding: EdgeInsets.only(bottom: AdaptiveSpacing.tiny),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: SizeConfig.adaptiveSize(24),
                          height: SizeConfig.adaptiveSize(24),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${entry.key + 1}',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: SizeConfig.adaptiveFontSize(12),
                            ),
                          ),
                        ),
                        SizedBox(width: AdaptiveSpacing.small),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: SizeConfig.adaptiveFontSize(14),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ] else ...[
              Text(
                'Aucune étape disponible.',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            ]
          ],
        ),
      ),
    );
  }
}
