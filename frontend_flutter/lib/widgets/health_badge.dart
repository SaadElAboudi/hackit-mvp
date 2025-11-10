import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_extensions.dart';

/// A small status badge that pings the backend /health endpoint and shows:
/// - Healthy (green) when HTTP 200
/// - Degraded (amber) if flags indicate fallback / mock / cached
/// - Down (red) on error or timeout
/// Clicking the badge refreshes the status.
class HealthBadge extends StatefulWidget {
  const HealthBadge({super.key});

  @override
  State<HealthBadge> createState() => _HealthBadgeState();
}

class _HealthBadgeState extends State<HealthBadge> {
  late Future<Map<String, dynamic>> _future;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = ApiService.create().pingHealth();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final palette = Theme.of(context).extension<AppPalette>();
        String label = 'Checking';
        Color color = (palette?.accentInfo ?? Colors.grey);
        Map<String, dynamic>? data = snap.data;
        if (snap.connectionState == ConnectionState.waiting) {
          label = '…';
        } else if (snap.hasError) {
          label = 'Down';
          color = palette?.accentDanger ?? Colors.red;
        } else if (data != null) {
          // Basic success
          final ok = data['ok'] == true ||
              data['status'] == 200 ||
              data['ok'] == null; // heuristics
          final fallback = data['fallback'] == true;
          final mock = data['mode'] == 'MOCK' || data['mock'] == true;
          final cached = data['cached'] == true;
          if (ok) {
            // degrade if any flag suggests non-real or fallback
            if (fallback || mock) {
              label = 'Degraded';
              color = palette?.accentWarning ?? Colors.amber;
            } else {
              label = 'Healthy';
              color = palette?.accentSuccess ?? Colors.green;
            }
            if (cached && label == 'Healthy') {
              // subtle variant
              label = 'Healthy*';
            }
            _lastUpdated = DateTime.now();
          } else {
            label = 'Down';
            color = palette?.accentDanger ?? Colors.red;
          }
        }

        return InkWell(
          onTap: _refresh,
          borderRadius: BorderRadius.circular(32),
          child: Tooltip(
            message: _buildTooltip(data, snap.hasError),
            waitDuration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dot(color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color.darken(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildTooltip(Map<String, dynamic>? data, bool error) {
    if (error) return 'Erreur de connexion. Cliquer pour réessayer.';
    if (data == null) return 'Rafraîchir le statut';
    final buf = StringBuffer();
    buf.writeln('Backend status');
    if (_lastUpdated != null) {
      buf.writeln('Dernier ping: ${_lastUpdated!.toIso8601String()}');
    }
    for (final entry in data.entries.take(12)) {
      buf.writeln('${entry.key}: ${entry.value}');
    }
    buf.writeln('\nTap pour rafraîchir');
    return buf.toString();
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

extension _ColorHelpers on Color {
  Color darken([double amount = .25]) {
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0, 1));
    return hslDark.toColor();
  }
}
