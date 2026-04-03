// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';

class SummaryView extends StatelessWidget {
  final String title;
  final List<String> steps;
  final String? deliveryMode;
  final String? source;
  const SummaryView({
    super.key,
    required this.title,
    required this.steps,
    this.deliveryMode,
    this.source,
  });

  String get _modeLabel {
    switch (deliveryMode) {
      case 'cadrer':
        return 'Cadrage';
      case 'produire':
        return 'Production';
      case 'communiquer':
        return 'Communication';
      case 'audit':
        return 'Audit 7 jours';
      default:
        return 'Plan d\'action';
    }
  }

  List<_PlanSection> _buildSections() {
    final cleanSteps = steps.where((step) => step.trim().isNotEmpty).toList();
    if (cleanSteps.isEmpty) {
      return const [
        _PlanSection(
          title: 'Aucun plan genere',
          items: ['Aucune etape exploitable n\'a ete retournee.'],
        ),
      ];
    }

    switch (deliveryMode) {
      case 'cadrer':
        return [
          _PlanSection(title: 'Objectif et contexte', items: cleanSteps.take(2).toList()),
          _PlanSection(title: 'Risques et contraintes', items: cleanSteps.skip(2).take(2).toList()),
          _PlanSection(title: 'Definition of done', items: cleanSteps.skip(4).toList()),
        ].where((section) => section.items.isNotEmpty).toList();
      case 'communiquer':
        return [
          _PlanSection(title: 'Message principal', items: cleanSteps.take(2).toList()),
          _PlanSection(title: 'Points a partager', items: cleanSteps.skip(2).take(2).toList()),
          _PlanSection(title: 'Call to action', items: cleanSteps.skip(4).toList()),
        ].where((section) => section.items.isNotEmpty).toList();
      case 'audit':
        return [
          _PlanSection(title: 'Constats', items: cleanSteps.take(2).toList()),
          _PlanSection(title: 'Quick wins', items: cleanSteps.skip(2).take(2).toList()),
          _PlanSection(title: 'Plan 7 jours', items: cleanSteps.skip(4).toList()),
        ].where((section) => section.items.isNotEmpty).toList();
      case 'produire':
      default:
        return [
          _PlanSection(title: 'Priorites', items: cleanSteps.take(2).toList()),
          _PlanSection(title: 'Checklist execution', items: cleanSteps.skip(2).take(3).toList()),
          _PlanSection(title: 'Livrable final', items: cleanSteps.skip(5).toList()),
        ].where((section) => section.items.isNotEmpty).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    final sections = _buildSections();

    return Card(
      elevation: 0,
      color: Colors.transparent,
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
              const Color(0xFFF7F7F4),
              scheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
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
                    color: const Color(0xFFEEF2EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    _modeLabel,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                if ((source ?? '').isNotEmpty)
                  Text(
                    source!,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            SizedBox(height: AdaptiveSpacing.medium),
            ...sections.asMap().entries.map(
                  (sectionEntry) => Padding(
                    padding: EdgeInsets.only(bottom: AdaptiveSpacing.medium),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sectionEntry.value.title,
                          style: TextStyle(
                            fontSize: SizeConfig.adaptiveFontSize(15),
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface.withValues(alpha: 0.88),
                          ),
                        ),
                        SizedBox(height: AdaptiveSpacing.small),
                        ...sectionEntry.value.items.asMap().entries.map(
                          (entry) => Padding(
                      padding: EdgeInsets.only(
                        bottom: AdaptiveSpacing.tiny + 2,
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(
                          milliseconds:
                              320 + (sectionEntry.key * 70) + (entry.key * 50),
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
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
                                width: 22.0,
                                height: 22.0,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF111111),
                                      scheme.primary.withValues(alpha: 0.85),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
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
                                  entry.value,
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
                      ],
                    ),
                  ),
                ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                deliveryMode == 'communiquer'
                    ? 'Utilise ce brouillon comme base, puis adapte le ton et la deadline avant envoi.'
                    : deliveryMode == 'cadrer'
                        ? 'Valide ce cadrage avec le client avant de lancer la production.'
                        : deliveryMode == 'audit'
                            ? 'Commence par les quick wins a faible effort pour montrer de la traction.'
                            : 'Vise un premier livrable partageable rapidement, puis itere.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSection {
  final String title;
  final List<String> items;
  const _PlanSection({required this.title, required this.items});
}
