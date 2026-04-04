// ignore_for_file: prefer_const_constructors
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
      title: Text('Chapitres (${chapters.length})',
          style: TextStyle(fontWeight: FontWeight.bold)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Column(
            children: [
              for (final ch in chapters)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: Colors.cyan,
                      child: Icon(Icons.play_arrow, color: Colors.white),
                    ),
                    title: Text(ch.title,
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w600)),
                    subtitle: Row(
                      children: [
                        Chip(
                          label: Text(_formatTs(ch.startSec),
                              style: TextStyle(color: Colors.white)),
                          backgroundColor: Colors.indigo,
                        ),
                        SizedBox(width: 8),
                        Text('Cliquez pour lire',
                            style:
                                TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                    ),
                    onTap: () {
                      if (_debouncing) return;
                      _debouncing = true;
                      Future.delayed(const Duration(milliseconds: 400), () {
                        _debouncing = false;
                      });
                      if (kIsWeb) {
                        seekYouTube(ch.startSec);
                      } else {
                        VideoSeekService.instance.seekOrQueue(ch.startSec,
                            sourceUrl: widget.videoUrl);
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
                      icon: const Icon(Icons.open_in_new,
                          color: Colors.cyanAccent, size: 22),
                      onPressed: () => _openExternal(context,
                          _withTimestamp(widget.videoUrl, ch.startSec)),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
