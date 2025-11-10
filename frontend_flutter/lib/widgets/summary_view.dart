// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';

class SummaryView extends StatelessWidget {
  final String title;
  final List<String> steps;
  const SummaryView({super.key, required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          AdaptiveSpacing.medium,
          AdaptiveSpacing.medium + 4,
          AdaptiveSpacing.medium,
          AdaptiveSpacing.medium,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.10),
              scheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.article_rounded, color: scheme.primary),
                ),
                SizedBox(width: AdaptiveSpacing.small),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20, // revert to keep test stable
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                      height: 1.12,
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
              ...steps.asMap().entries.map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(
                        bottom: AdaptiveSpacing.tiny + 2,
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(
                          milliseconds: 350 + (entry.key * 60),
                        ),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, (1 - t) * 12),
                            child: child,
                          ),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            AdaptiveSpacing.small,
                            AdaptiveSpacing.small + 2,
                            AdaptiveSpacing.small,
                            AdaptiveSpacing.small + 4,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 20.0,
                                height: 20.0,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      scheme.primary.withValues(alpha: 0.85),
                                      scheme.primaryContainer
                                          .withValues(alpha: 0.9),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.0,
                                  ),
                                ),
                              ),
                              SizedBox(width: AdaptiveSpacing.small),
                              Expanded(
                                child: Text(
                                  '${entry.key + 1}. ${entry.value}',
                                  style: TextStyle(
                                    fontSize: SizeConfig.adaptiveFontSize(14),
                                    height: 1.32,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
