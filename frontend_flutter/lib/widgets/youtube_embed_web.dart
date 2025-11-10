// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';

// Simplified web implementation: remove fixed iframe and show a button to open the video externally.
// This avoids layout issues and blank iframe scenarios. Seeking inline is no longer supported.

Widget buildYouTubeEmbed(String url) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_fill,
                    size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  'Vidéo disponible',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ouvrir la vidéo YouTube dans un nouvel onglet pour la lecture et les chapitres.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _openExternal(url),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ouvrir sur YouTube'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// No-op: inline seek removed.
void seekYouTube(int seconds) {}

void _openExternal(String url) {
  // Attempt to normalize watch URL if user passed embed or short URL.
  try {
    final uri = Uri.parse(url);
    String? id;
    if (uri.host.contains('youtu.be')) {
      id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (uri.queryParameters['v'] != null) {
      id = uri.queryParameters['v'];
    } else {
      final idx = uri.pathSegments.indexOf('embed');
      if (idx != -1 && idx + 1 < uri.pathSegments.length) {
        id = uri.pathSegments[idx + 1];
      }
    }
    final watch = id != null ? 'https://www.youtube.com/watch?v=$id' : url;
    // ignore: avoid_print
    html.window.open(watch, '_blank');
  } catch (_) {
    // Fallback: just open the original URL.
    // ignore: avoid_print
    print('Open external video: $url');
  }
}
