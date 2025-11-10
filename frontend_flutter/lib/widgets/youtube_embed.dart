import 'package:flutter/material.dart';
import 'youtube_embed_io.dart' if (dart.library.html) 'youtube_embed_web.dart'
    as impl;

class YouTubeEmbed extends StatelessWidget {
  final String videoUrl;
  const YouTubeEmbed({super.key, required this.videoUrl});

  @override
  Widget build(BuildContext context) {
    return impl.buildYouTubeEmbed(videoUrl);
  }
}
