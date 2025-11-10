import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/base_search_result.dart';
import '../services/video_seek_service.dart';
import 'youtube_embed.dart';

class ChaptersView extends StatefulWidget {
  final List<Chapter> chapters;
  final String videoUrl;
  const ChaptersView(
      {super.key, required this.chapters, required this.videoUrl});

  @override
  State<ChaptersView> createState() => _ChaptersViewState();
}

class _ChaptersViewState extends State<ChaptersView> {
  bool _debouncing = false;

  @override
  Widget build(BuildContext context) {
    final chapters = widget.chapters;
    if (chapters.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text('Chapitres (${chapters.length})'),
      children: [
        for (final ch in chapters)
          ListTile(
            dense: true,
            title: Text(ch.title),
            leading: const Icon(Icons.play_arrow, size: 20),
            subtitle: Text(_formatTs(ch.startSec)),
            onTap: () {
              if (_debouncing) return;
              _debouncing = true;
              Future.delayed(const Duration(milliseconds: 400), () {
                _debouncing = false;
              });
              if (kIsWeb) {
                // Attempt inline seek; fallback to service queue if not available.
                seekYouTube(ch.startSec);
              } else {
                VideoSeekService.instance
                    .seekOrQueue(ch.startSec, sourceUrl: widget.videoUrl);
              }
              final messenger = ScaffoldMessenger.of(context);
              messenger.hideCurrentSnackBar();
              final ts = _formatTs(ch.startSec);
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Lecture à $ts'),
                  duration: const Duration(milliseconds: 900),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            trailing: IconButton(
              tooltip: 'Ouvrir dans une nouvelle fenêtre',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => _openExternal(
                  context, _withTimestamp(widget.videoUrl, ch.startSec)),
            ),
          )
      ],
    );
  }

  String _formatTs(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _withTimestamp(String url, int startSec) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final params = Map<String, String>.from(uri.queryParameters);
    params['t'] = startSec.toString();
    return uri.replace(queryParameters: params).toString();
  }

  void _openExternal(BuildContext context, String url) {
    // For now keep simple: print; future: use url_launcher to open in new tab/window.
    // ignore: avoid_print
    print('External chapter URL: $url');
  }
}
