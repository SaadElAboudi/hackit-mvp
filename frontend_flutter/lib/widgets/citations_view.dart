import 'package:flutter/material.dart';
import '../models/base_search_result.dart';
import '../services/video_seek_service.dart';

class CitationsView extends StatelessWidget {
  final List<Citation> citations;
  const CitationsView({super.key, required this.citations});

  @override
  Widget build(BuildContext context) {
    if (citations.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: citations.take(6).map((c) {
        final label = _formatTs(c.startSec);
        return Tooltip(
          message: 'Aller à $label',
          child: OutlinedButton.icon(
            onPressed: () => VideoSeekService.instance
                .seekOrQueue(c.startSec, sourceUrl: c.url),
            icon: const Icon(Icons.access_time, size: 16),
            label: Text(label),
          ),
        );
      }).toList(),
    );
  }

  String _formatTs(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // External opening removed; now we prioritize in-app seeking via VideoSeekService.
}
