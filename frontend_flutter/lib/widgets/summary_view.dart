// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';

class SummaryView extends StatelessWidget {
  final String title;
  final List<String> steps;
  final String? deliveryMode;
  final String? source;
  final Map<String, dynamic>? deliveryPlan;
  const SummaryView({
    super.key,
    required this.title,
    required this.steps,
    this.deliveryMode,
    this.source,
    this.deliveryPlan,
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

  Widget? _buildStrategyCards(BuildContext ctx) {
    final plan = deliveryPlan;
    if (plan == null) return null;
    final raw = plan['strategyVariants'];
    if (raw is! List || raw.isEmpty) return null;
    final variants = raw.whereType<Map>().toList();
    if (variants.isEmpty) return null;
    final scheme = Theme.of(ctx).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows_rounded,
                size: 14, color: scheme.primary.withValues(alpha: 0.85)),
            const SizedBox(width: 5),
            Text(
              '3 stratégies disponibles',
              style: TextStyle(
                fontSize: SizeConfig.adaptiveFontSize(15),
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ],
        ),
        SizedBox(height: AdaptiveSpacing.small),
        LayoutBuilder(
          builder: (_, constraints) {
            final wide = constraints.maxWidth > 480;
            final cards = variants
                .map((v) => _StrategyCard(variant: v, scheme: scheme))
                .toList();
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cards
                    .asMap()
                    .entries
                    .map((e) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: e.key < cards.length - 1 ? 8 : 0),
                            child: e.value,
                          ),
                        ))
                    .toList(),
              );
            }
            return Column(
              children: cards
                  .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8), child: c))
                  .toList(),
            );
          },
        ),
        SizedBox(height: AdaptiveSpacing.medium),
      ],
    );
  }

  List<_PlanSection> _buildSections() {
    final plan = deliveryPlan;
    if (plan != null && plan.isNotEmpty) {
      List<String> listOf(String key) {
        final value = plan[key];
        if (value is List) {
          return value
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList();
        }
        if (value is String && value.trim().isNotEmpty) return [value.trim()];
        return const <String>[];
      }

      final fromPlan = [
        _PlanSection(title: 'Objectif', items: listOf('objective')),
        _PlanSection(title: 'Prochaines actions', items: listOf('nextActions')),
        _PlanSection(title: 'Timeline', items: listOf('timeline')),
        _PlanSection(title: "Critères d'acceptation", items: listOf('acceptanceCriteria')),
        _PlanSection(title: 'Périmètre', items: listOf('scope')),
        _PlanSection(title: 'Risques', items: listOf('risks')),
        _PlanSection(title: 'Effort', items: listOf('effort')),
        _PlanSection(title: 'Dépendances', items: listOf('dependencies')),
      ].where((section) => section.items.isNotEmpty).toList();

      if (fromPlan.isNotEmpty) return fromPlan;
    }

    final cleanSteps = steps.where((step) => step.trim().isNotEmpty).toList();
    if (cleanSteps.isEmpty) {
      return const [
        _PlanSection(
          title: 'Aucun plan généré',
          items: ["Aucune étape exploitable n'a été retournée."],
        ),
      ];
    }

    switch (deliveryMode) {
      case 'cadrer':
        return [
          _PlanSection(
              title: 'Objectif et contexte',
              items: cleanSteps.take(2).toList()),
          _PlanSection(
              title: 'Risques et contraintes',
              items: cleanSteps.skip(2).take(2).toList()),
          _PlanSection(
              title: 'Définition du livrable',
              items: cleanSteps.skip(4).toList()),
        ].where((section) => section.items.isNotEmpty).toList();
      case 'communiquer':
        return [
          _PlanSection(
              title: 'Message principal', items: cleanSteps.take(2).toList()),
          _PlanSection(
              title: 'Points à partager',
              items: cleanSteps.skip(2).take(2).toList()),
          _PlanSection(
              title: 'Call to action', items: cleanSteps.skip(4).toList()),
        ].where((section) => section.items.isNotEmpty).toList();
      case 'audit':
        return [
          _PlanSection(title: 'Constats', items: cleanSteps.take(2).toList()),
          _PlanSection(
              title: 'Quick wins', items: cleanSteps.skip(2).take(2).toList()),
          _PlanSection(
              title: 'Plan 7 jours', items: cleanSteps.skip(4).toList()),
        ].where((section) => section.items.isNotEmpty).toList();
      case 'produire':
      default:
        return [
          _PlanSection(title: 'Priorités', items: cleanSteps.take(2).toList()),
          _PlanSection(
              title: 'Checklist exécution',
              items: cleanSteps.skip(2).take(3).toList()),
          _PlanSection(
              title: 'Livrable final', items: cleanSteps.skip(5).toList()),
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
              scheme.surfaceContainerLow,
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
                    color: scheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    _modeLabel,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
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
            ...() {
              final sc = _buildStrategyCards(context);
              return sc != null ? [sc] : <Widget>[];
            }(),
            ...() {
              final raw = deliveryPlan?['readyToSend'];
              if (raw is String && raw.trim().isNotEmpty) {
                return [
                  _ReadyToSendCard(
                    text: raw,
                    mode: deliveryMode ?? 'produire',
                  ),
                  SizedBox(height: AdaptiveSpacing.medium),
                ];
              }
              return <Widget>[];
            }(),
            _ExpandableSections(sections: sections),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                deliveryMode == 'communiquer'
                    ? 'Utilise ce brouillon comme base, puis adapte le ton et la deadline avant envoi.'
                    : deliveryMode == 'cadrer'
                        ? 'Valide ce cadrage avec le client avant de lancer la production.'
                        : deliveryMode == 'audit'
                            ? 'Commence par les quick wins à faible effort pour montrer de la traction.'
                            : 'Vise un premier livrable partageable rapidement, puis itère.',
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

/// Shows plan sections with progressive disclosure (first 4 visible, rest expandable).
class _ExpandableSections extends StatefulWidget {
  final List<_PlanSection> sections;
  const _ExpandableSections({required this.sections});

  @override
  State<_ExpandableSections> createState() => _ExpandableSectionsState();
}

class _ExpandableSectionsState extends State<_ExpandableSections> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    final visible = _expanded
        ? widget.sections
        : widget.sections.take(4).toList();

    Widget buildItem(int sectionIdx, _PlanSection section, int itemIdx,
        String value) {
      return Padding(
        padding: EdgeInsets.only(bottom: AdaptiveSpacing.tiny + 2),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(
              milliseconds: 320 + (sectionIdx * 60) + (itemIdx * 40)),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
                offset: Offset(0, (1 - t) * 10), child: child),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.25),
                  width: 1),
            ),
            padding: EdgeInsets.fromLTRB(AdaptiveSpacing.small,
                AdaptiveSpacing.small + 2, AdaptiveSpacing.small,
                AdaptiveSpacing.small + 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
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
                    '${itemIdx + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
                SizedBox(width: AdaptiveSpacing.small),
                Expanded(
                  child: Text(value,
                      style: TextStyle(
                          fontSize: SizeConfig.adaptiveFontSize(14),
                          height: 1.32)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...visible.asMap().entries.map((se) => Padding(
              padding: EdgeInsets.only(bottom: AdaptiveSpacing.medium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_iconForSection(se.value.title) != null) ...[
                        Icon(_iconForSection(se.value.title)!,
                            size: 14,
                            color: scheme.primary.withValues(alpha: 0.85)),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          se.value.title,
                          style: TextStyle(
                            fontSize: SizeConfig.adaptiveFontSize(15),
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                      _CopyIconButton(items: se.value.items),
                    ],
                  ),
                  SizedBox(height: AdaptiveSpacing.small),
                  ...se.value.items.asMap().entries.map(
                        (ie) => buildItem(se.key, se.value, ie.key, ie.value),
                      ),
                ],
              ),
            )),
        if (!_expanded && widget.sections.length > 4)
          Padding(
            padding: EdgeInsets.only(bottom: AdaptiveSpacing.medium),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
              onPressed: () => setState(() => _expanded = true),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text(
                'Voir ${widget.sections.length - 4} autres éléments',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlanSection {
  final String title;
  final List<String> items;
  const _PlanSection({required this.title, required this.items});
}

IconData? _iconForSection(String title) {
  const map = <String, IconData>{
    'Objectif': Icons.flag_rounded,
    'Périmètre': Icons.crop_square_rounded,
    'Risques': Icons.warning_amber_rounded,
    'Prochaines actions': Icons.bolt_rounded,
    'Timeline': Icons.calendar_today_rounded,
    'Effort': Icons.speed_rounded,
    'Dépendances': Icons.link_rounded,
    "Critères d'acceptation": Icons.check_circle_outline_rounded,
    'Message client': Icons.chat_bubble_outline_rounded,
    'Priorisation impact/effort': Icons.balance_rounded,
    'Score qualité': Icons.auto_graph_rounded,
    'Vérifications de cohérence': Icons.fact_check_rounded,
    'Alertes de cohérence': Icons.report_problem_outlined,
    'Objectif et contexte': Icons.flag_rounded,
    'Risques et contraintes': Icons.warning_amber_rounded,
    'Définition du livrable': Icons.description_rounded,
    'Message principal': Icons.chat_bubble_outline_rounded,
    'Points à partager': Icons.format_list_bulleted_rounded,
    'Call to action': Icons.bolt_rounded,
    'Constats': Icons.visibility_rounded,
    'Quick wins': Icons.electric_bolt_rounded,
    'Plan 7 jours': Icons.calendar_month_rounded,
    'Priorités': Icons.priority_high_rounded,
    'Checklist exécution': Icons.checklist_rounded,
    'Livrable final': Icons.description_rounded,
    'Aucun plan généré': Icons.info_outline_rounded,
  };
  return map[title];
}

class _StrategyCard extends StatelessWidget {
  final Map variant;
  final ColorScheme scheme;
  const _StrategyCard({required this.variant, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final recommended = variant['recommended'] == true;
    final gains = (variant['estimatedGains'] as List?)
            ?.map((e) => e.toString())
            .take(3)
            .toList() ??
        [];
    final risks = (variant['risks'] as List?)
            ?.map((e) => e.toString())
            .take(2)
            .toList() ??
        [];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: recommended
            ? scheme.primaryContainer.withValues(alpha: 0.25)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: recommended
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.3),
          width: recommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(variant['emoji']?.toString() ?? '',
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  variant['label']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: recommended ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
              if (recommended)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '★ Recommandé',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            variant['description']?.toString() ?? '',
            style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurface.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '⏱ ${variant['effort'] ?? ''}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
          ),
          if (gains.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...gains.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('✓ ',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.bold)),
                      Expanded(
                          child: Text(g,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.8)))),
                    ],
                  ),
                )),
          ],
          if (risks.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...risks.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚠ ',
                          style: TextStyle(
                              fontSize: 11, color: Colors.orange.shade600)),
                      Expanded(
                          child: Text(r,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.65)))),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _CopyIconButton extends StatefulWidget {
  final List<String> items;
  const _CopyIconButton({required this.items});

  @override
  State<_CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<_CopyIconButton> {
  bool _copied = false;

  Future<void> _copy() async {
    final text = widget.items.map((e) => '\u2022 $e').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Section copiée'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Copier',
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            _copied ? Icons.check_rounded : Icons.content_copy_rounded,
            size: 15,
            color: _copied
                ? Colors.green.shade600
                : scheme.onSurface.withValues(alpha: 0.30),
          ),
        ),
      ),
    );
  }
}

/// Prominent card showing the ready-to-send formatted deliverable.
class _ReadyToSendCard extends StatefulWidget {
  final String text;
  final String mode;
  const _ReadyToSendCard({required this.text, required this.mode});

  @override
  State<_ReadyToSendCard> createState() => _ReadyToSendCardState();
}

class _ReadyToSendCardState extends State<_ReadyToSendCard> {
  bool _collapsed = false;
  bool _copied = false;

  String get _title {
    switch (widget.mode) {
      case 'communiquer':
        return '✉️  Email prêt à envoyer';
      case 'cadrer':
        return '📋  Note de cadrage';
      case 'audit':
        return '🔍  Synthèse d\'audit';
      default:
        return '📄  Plan de livraison';
    }
  }

  /// Renders a single line as a styled widget based on its content.
  Widget _renderLine(String line, ColorScheme scheme) {
    final trimmed = line.trim();

    // Separator lines — render as visual divider
    if (trimmed.startsWith('═══') || trimmed.startsWith('───')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
          thickness: 1,
          height: 1,
        ),
      );
    }

    // Subsection headers (━━ P0, ━━ P1, etc.)
    if (trimmed.startsWith('━━')) {
      final text = trimmed.replaceAll('━', '').trim();
      final isP0 = text.contains('P0') || text.contains('BLOQUANT');
      final isP1 = text.contains('P1') || text.contains('IMPORTANT');
      final color = isP0
          ? Colors.red.shade700
          : isP1
              ? Colors.orange.shade700
              : scheme.primary;
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    // Empty lines — small spacing
    if (trimmed.isEmpty) {
      return const SizedBox(height: 4);
    }

    // RULES footer line (grayed out)
    if (trimmed.startsWith('RÈGLES')) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          trimmed,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.4,
            color: scheme.onSurface.withValues(alpha: 0.35),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // ALL-CAPS section headers (e.g. DIAGNOSTIC, ANSWER FIRST, VERDICT GLOBAL)
    final isAllCaps = trimmed.length > 2 &&
        trimmed == trimmed.toUpperCase() &&
        RegExp(r'[A-ZÀÂÄÉÈÊËÎÏÔÙÛÜ]').hasMatch(trimmed);
    if (isAllCaps && !trimmed.startsWith('•') && !trimmed.startsWith('→')) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 3),
        child: Text(
          trimmed,
          style: TextStyle(
            fontSize: SizeConfig.adaptiveFontSize(12.5),
            fontWeight: FontWeight.w800,
            color: scheme.primary.withValues(alpha: 0.9),
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    // Action arrows → (action items in accent color)
    if (trimmed.startsWith('→')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('→ ',
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(13.5),
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  height: 1.45,
                )),
            Expanded(
              child: Text(
                trimmed.substring(1).trim(),
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(13.5),
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Checkmark items ☑
    if (trimmed.startsWith('☑')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('☑ ',
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(13.5),
                  color: Colors.green.shade600,
                  height: 1.45,
                )),
            Expanded(
              child: Text(
                trimmed.substring(1).trim(),
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(13.5),
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Bullet points •
    if (trimmed.startsWith('•')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ',
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(14),
                  color: scheme.primary.withValues(alpha: 0.7),
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                )),
            Expanded(
              child: Text(
                trimmed.substring(1).trim(),
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(13.5),
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Numbered items (1. 2. 3.)
    final numberedMatch = RegExp(r'^(\d+)[.)]\s+(.+)$').firstMatch(trimmed);
    if (numberedMatch != null) {
      final num = numberedMatch.group(1)!;
      final content = numberedMatch.group(2)!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(right: 8, top: 1),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                num,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            Expanded(
              child: Text(
                content,
                style: TextStyle(
                  fontSize: SizeConfig.adaptiveFontSize(13.5),
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default: plain paragraph text
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        trimmed,
        style: TextStyle(
          fontSize: SizeConfig.adaptiveFontSize(13.5),
          height: 1.5,
          color: scheme.onSurface.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    final lines = widget.text.split('\n');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.25),
            scheme.secondaryContainer.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: TextStyle(
                    fontSize: SizeConfig.adaptiveFontSize(15),
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _copied
                    ? Row(
                        key: const ValueKey('done'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 14, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                          Text('Copié !',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade600,
                                  fontWeight: FontWeight.w600)),
                        ],
                      )
                    : FilledButton.icon(
                        key: const ValueKey('copy'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: widget.text));
                          if (!mounted) return;
                          setState(() => _copied = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) setState(() => _copied = false);
                          });
                        },
                        icon: const Icon(Icons.copy_rounded, size: 13),
                        label: const Text('Copier tout'),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Rich-rendered document body
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _collapsed
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...lines.take(8).map((l) => _renderLine(l, scheme)),
                const SizedBox(height: 6),
              ],
            ),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map((l) => _renderLine(l, scheme)).toList(),
            ),
          ),
          // Collapse toggle
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => setState(() => _collapsed = !_collapsed),
            icon: Icon(
                _collapsed
                    ? Icons.expand_more_rounded
                    : Icons.expand_less_rounded,
                size: 16),
            label: Text(
              _collapsed ? 'Voir le livrable complet' : 'Réduire',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
