import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lessons_provider.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/summary_view.dart';
import '../widgets/video_card.dart';
import '../widgets/youtube_embed.dart';

class LessonView extends StatelessWidget {
  final String title;
  final List<String> steps;
  final String videoUrl;
  final List<String>? transcript;
  final List<String>? chapters;
  const LessonView({
    super.key,
    required this.title,
    required this.steps,
    required this.videoUrl,
    this.transcript,
    this.chapters,
  });

  @override
  Widget build(BuildContext context) {
    final lessons = context.read<LessonsProvider>();
    final alreadySaved =
        lessons.lessons.any((l) => l.title == title && l.videoUrl == videoUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SummaryView(title: title, steps: steps),
        SizedBox(height: AdaptiveSpacing.medium),
        YouTubeEmbed(videoUrl: videoUrl),
        SizedBox(height: AdaptiveSpacing.small),
        VideoCard(title: title, videoUrl: videoUrl),
        SizedBox(height: AdaptiveSpacing.small),
        if (transcript != null && transcript!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transcript',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...transcript!.map((t) => Text(t)).toList(),
              ],
            ),
          ),
        if (chapters != null && chapters!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chapitres',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...chapters!.map((c) => Text(c)).toList(),
              ],
            ),
          ),
        if (!alreadySaved)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.save_rounded),
              label: const Text('Enregistrer comme leçon'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final created = await lessons.saveFromChat(
                    title: title,
                    steps: steps,
                    videoUrl: videoUrl,
                  );
                  if (created != null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Leçon enregistrée.')),
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          lessons.error ?? 'Échec de l\'enregistrement',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Erreur: $e')),
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}
