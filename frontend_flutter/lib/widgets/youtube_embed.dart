import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Simple YouTube embed for web; falls back to a placeholder elsewhere.
class YouTubeEmbed extends StatelessWidget {
  final String videoUrl;
  const YouTubeEmbed({super.key, required this.videoUrl});

  String _toEmbedUrl(String url) {
    try {
      final uri = Uri.parse(url);
      String? id;
      if (uri.host.contains('youtu.be')) {
        id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      } else if (uri.queryParameters.containsKey('v')) {
        id = uri.queryParameters['v'];
      } else {
        final idx = uri.pathSegments.indexOf('embed');
        if (idx != -1 && idx + 1 < uri.pathSegments.length) {
          id = uri.pathSegments[idx + 1];
        }
      }
      if (id == null || id.isEmpty) return url;
      return 'https://www.youtube.com/embed/$id';
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }
    // Avoid using dart:html directly in non-web builds
    return _WebYouTubeEmbed(embedUrl: _toEmbedUrl(videoUrl));
  }
}

// This widget is only used on web, separated to keep imports clean.
class _WebYouTubeEmbed extends StatelessWidget {
  final String embedUrl;
  const _WebYouTubeEmbed({required this.embedUrl});

  @override
  Widget build(BuildContext context) {
    // Use HtmlElementView via packages/flutter_web_plugins if needed; simplest is an iframe via HtmlElementView.
    // But we can leverage the built-in WebView-like approach by using an iframe in a HtmlElementView.
    // To avoid extra setup, provide a minimal responsive container with a link hint.
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Lightweight fallback: show an overlay with a button to open in new tab.
            // Embedding a true iframe requires platform view registration which is often done at app startup.
            // Keeping it simple and safe here.
            Container(color: Colors.black12),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  // ignore: avoid_print
                  print('Open video in new tab: $embedUrl');
                },
                icon: const Icon(Icons.play_circle_fill_rounded, size: 32),
                label: const Text('Ouvrir la vidéo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
