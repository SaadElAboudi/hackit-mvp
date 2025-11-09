import 'package:flutter/material.dart';
import '../models/base_search_result.dart';

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
        return OutlinedButton.icon(
          onPressed: () => _openExternal(context, c.url),
          icon: const Icon(Icons.link, size: 16),
          label: Text(label),
        );
      }).toList(),
    );
  }

  String _formatTs(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _openExternal(BuildContext context, String url) {
    // For web, Window.open; on mobile, use url_launcher if available.
    // To avoid adding dependencies, rely on Navigator to open via external app when possible.
    // If url_launcher is present in project, swap to launchUrl.
    // ignore: avoid_print
    print('Open URL: $url');
  }
}
