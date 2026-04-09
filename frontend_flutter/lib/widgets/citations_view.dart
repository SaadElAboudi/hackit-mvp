import 'package:flutter/material.dart';
// ...existing code...
import '../models/base_search_result.dart';
import 'youtube_embed.dart';

class CitationsView extends StatelessWidget {
  final List<Citation> citations;
  const CitationsView({super.key, required this.citations});

  @override
  Widget build(BuildContext context) {
    if (citations.isEmpty) return const SizedBox.shrink();
    // ...existing code...
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: citations.take(6).map((c) {
        final label = _formatTs(c.startSec);
        return Tooltip(
          message: 'Aller à $label',
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: InkWell(
              onTap: () => seekYouTube(c.startSec),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time,
                      size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(color: Colors.black)),
                ],
              ),
            ),
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
