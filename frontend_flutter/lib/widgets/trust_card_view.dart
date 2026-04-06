import 'package:flutter/material.dart';

/// Displays the "Carte de confiance" for a deliverable:
/// why this plan, key assumptions, limits, optional key insight, and a
/// confidence badge (élevé / moyen / faible).
///
/// Reads from deliveryPlan['trustCard']:
/// {
///   confidence: 'élevé' | 'moyen' | 'faible',
///   whyThisPlan: String,
///   assumptions: List<String>,
///   limits: String,
///   keyInsight?: String,
/// }
class TrustCardView extends StatelessWidget {
  final Map<String, dynamic>? deliveryPlan;

  const TrustCardView({super.key, required this.deliveryPlan});

  @override
  Widget build(BuildContext context) {
    final tc = deliveryPlan?['trustCard'];
    if (tc is! Map) return const SizedBox.shrink();

    final confidence = (tc['confidence'] as String?) ?? 'moyen';
    final whyThisPlan = (tc['whyThisPlan'] as String?) ?? '';
    final rawAssumptions = tc['assumptions'];
    final assumptions = rawAssumptions is List
        ? rawAssumptions.whereType<String>().toList()
        : <String>[];
    final limits = (tc['limits'] as String?) ?? '';
    final keyInsight = tc['keyInsight'] as String?;

    if (whyThisPlan.isEmpty && assumptions.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _confidenceBorderColor(confidence).withValues(alpha: 0.35),
        ),
      ),
      color: _confidenceBgColor(confidence, scheme),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          Icons.shield_outlined,
          color: _confidenceIconColor(confidence),
          size: 20,
        ),
        title: Row(
          children: [
            Text(
              'Carte de confiance',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            _ConfidenceBadge(confidence: confidence),
          ],
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (whyThisPlan.isNotEmpty) ...[
            _SectionRow(
              icon: Icons.lightbulb_outline_rounded,
              iconColor: scheme.primary,
              label: 'Pourquoi ce plan',
              content: whyThisPlan,
            ),
            const SizedBox(height: 10),
          ],
          if (assumptions.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.checklist_rounded,
                    size: 14, color: scheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 5),
                Text(
                  'Hypothèses',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...assumptions.map((a) => Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ',
                          style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.55),
                              fontSize: 13)),
                      Expanded(
                        child: Text(
                          a,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 10),
          ],
          if (limits.isNotEmpty)
            _SectionRow(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.orange.shade600,
              label: 'Limite',
              content: limits,
            ),
          if (keyInsight != null && keyInsight.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: scheme.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      keyInsight,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _confidenceBorderColor(String c) {
    switch (c) {
      case 'élevé':
        return Colors.green.shade600;
      case 'faible':
        return Colors.red.shade400;
      default:
        return Colors.amber.shade600;
    }
  }

  Color _confidenceBgColor(String c, ColorScheme scheme) {
    switch (c) {
      case 'élevé':
        return Colors.green.shade50.withValues(alpha: 0.35);
      case 'faible':
        return Colors.red.shade50.withValues(alpha: 0.3);
      default:
        return Colors.amber.shade50.withValues(alpha: 0.3);
    }
  }

  Color _confidenceIconColor(String c) {
    switch (c) {
      case 'élevé':
        return Colors.green.shade600;
      case 'faible':
        return Colors.red.shade500;
      default:
        return Colors.amber.shade700;
    }
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final String confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (confidence) {
      'élevé' => (
          'Confiance élevée',
          Colors.green.shade100,
          Colors.green.shade800
        ),
      'faible' => (
          'Confiance faible',
          Colors.red.shade100,
          Colors.red.shade800
        ),
      _ => ('Confiance moyenne', Colors.amber.shade100, Colors.amber.shade900),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String content;

  const _SectionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label : ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                TextSpan(
                  text: content,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
