import 'package:flutter/widgets.dart';

Widget buildYouTubeEmbed(String url) {
  // Non-web platforms: no inline iframe; let the VideoCard handle opening.
  return const SizedBox.shrink();
}

// No-op seek for non-web platforms.
void seekYouTube(int seconds) {}
