import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// In-place Devil's Advocate section: streams a structured critique of the plan.
class ChallengeSection extends StatefulWidget {
  final String deliverable;
  final String query;
  final String mode;

  const ChallengeSection({
    super.key,
    required this.deliverable,
    required this.query,
    required this.mode,
  });

  @override
  State<ChallengeSection> createState() => _ChallengeSectionState();
}

class _ChallengeSectionState extends State<ChallengeSection> {
  bool _loading = false;
  bool _expanded = false;
  List<String> _lines = [];
  String? _error;

  Future<void> _runChallenge() async {
    setState(() {
      _loading = true;
      _lines = [];
      _error = null;
      _expanded = true;
    });

    try {
      final api = ApiService.create();
      final stream = api.challengeStream(
        widget.deliverable,
        widget.query,
        widget.mode,
      );
      await for (final evt in stream) {
        if (!mounted) return;
        if (evt.type == 'partial' && (evt.step ?? '').isNotEmpty) {
          setState(() => _lines = [..._lines, evt.step!.trim()]);
        } else if (evt.type == 'error') {
          setState(() => _error = evt.message ?? 'Erreur inattendue');
          break;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trigger button
        if (!_expanded)
          Tooltip(
            message: 'Jouer l\'avocat du diable sur ce plan',
            child: TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.orange.shade700,
              ),
              icon: const Icon(Icons.gavel_rounded, size: 18),
              label: const Text('Challenger ce plan',
                  style: TextStyle(fontSize: 13)),
              onPressed: _runChallenge,
            ),
          ),

        // Critique panel
        if (_expanded) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.orange.shade200,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gavel_rounded,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Avocat du diable',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const Spacer(),
                    if (!_loading)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.refresh_rounded,
                                size: 16, color: Colors.orange.shade600),
                            tooltip: 'Relancer l\'analyse',
                            onPressed: _runChallenge,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close_rounded,
                                size: 16,
                                color: scheme.onSurface.withValues(alpha: 0.4)),
                            tooltip: 'Fermer',
                            onPressed: () =>
                                setState(() => _expanded = false),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loading && _lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Analyse en cours...',
                            style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 13,
                    ),
                  ),
                ..._lines.map((line) => _CritiqueLine(text: line)),
                if (_loading && _lines.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.orange.shade600),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CritiqueLine extends StatelessWidget {
  final String text;
  const _CritiqueLine({required this.text});

  Color _color() {
    if (text.contains('🔴')) return Colors.red.shade700;
    if (text.contains('⚠️')) return Colors.orange.shade700;
    if (text.contains('💬')) return Colors.purple.shade700;
    if (text.contains('✅')) return Colors.green.shade700;
    if (text.contains('⚡')) return Colors.blue.shade700;
    return Colors.grey.shade800;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) =>
          Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child)),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: _color(),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
