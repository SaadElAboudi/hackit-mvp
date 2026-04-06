import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plan_feedback_provider.dart';

/// Inline feedback widget placed at the bottom of a plan.
/// Lets the user rate: 👍 Pertinent / 🤷 Moyen / 👎 Hors-sujet
/// After rating: shows optional reason text field + confirm button.
class PlanFeedbackWidget extends StatefulWidget {
  final String query;
  final String mode;

  const PlanFeedbackWidget({
    super.key,
    required this.query,
    required this.mode,
  });

  @override
  State<PlanFeedbackWidget> createState() => _PlanFeedbackWidgetState();
}

class _PlanFeedbackWidgetState extends State<PlanFeedbackWidget> {
  String? _selected; // 'pertinent' | 'moyen' | 'hors-sujet'
  bool _showReason = false;
  bool _submitted = false;
  final _reasonCtrl = TextEditingController();

  static const _options = [
    ('pertinent', '👍', 'Pertinent'),
    ('moyen', '🤷', 'Moyen'),
    ('hors-sujet', '👎', 'Hors-sujet'),
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill if already rated
    final existing = context
        .read<PlanFeedbackProvider>()
        .getFeedback(widget.query, widget.mode);
    if (existing != null) {
      _selected = existing.rating;
      _submitted = true;
      if (existing.reason != null) {
        _reasonCtrl.text = existing.reason!;
      }
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit({bool withReason = false}) async {
    final provider = context.read<PlanFeedbackProvider>();
    await provider.saveFeedback(
      widget.query,
      widget.mode,
      _selected!,
      reason: withReason ? _reasonCtrl.text : null,
    );
    if (mounted) {
      setState(() {
        _submitted = true;
        _showReason = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // If already submitted and no rating change → show compact "merci" state
    if (_submitted && !_showReason) {
      final (_, emoji, label) = _options.firstWhere(
        (o) => o.$1 == _selected,
        orElse: () => _options[1],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(
          children: [
            Text(
              '$emoji Noté : $label',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() {
                _submitted = false;
                _selected = null;
              }),
              child: Text(
                'Modifier',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.primary.withValues(alpha: 0.6),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ce plan vous a-t-il été utile ?',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _options.map((opt) {
              final (value, emoji, label) = opt;
              final isSelected = _selected == value;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  child: ChoiceChip(
                    label: Text(
                      '$emoji $label',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selected = value;
                        _showReason = true;
                        _submitted = false;
                      });
                    },
                    selectedColor: scheme.primary.withValues(alpha: 0.15),
                    side: BorderSide(
                      color: isSelected
                          ? scheme.primary.withValues(alpha: 0.5)
                          : scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              );
            }).toList(),
          ),
          if (_showReason && _selected != null) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _reasonCtrl,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(
                hintText:
                    'Une raison ? (optionnel — ex: trop générique, manque de chiffres…)',
                hintStyle: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.4)),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                counterStyle: TextStyle(fontSize: 10, color: scheme.outline),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilledButton.tonal(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity(horizontal: -2, vertical: -2),
                    textStyle:
                        WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                  ),
                  onPressed: () => _submit(withReason: true),
                  child: const Text('Envoyer'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _submit(),
                  child: Text(
                    'Passer',
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.45)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
