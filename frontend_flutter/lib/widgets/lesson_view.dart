import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lessons_provider.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/summary_view.dart';
import '../widgets/video_card.dart';
import '../widgets/youtube_embed.dart';
import '../models/base_search_result.dart';
import 'chapters_view.dart';

List<Chapter> chaptersFromAny(List chapters) {
  return chapters.map((c) {
    if (c is Chapter) return c;
    if (c is Map<String, dynamic>) {
      return Chapter(
        index: (c['index'] as num?)?.toInt() ?? 0,
        startSec: (c['startSec'] as num?)?.toInt() ?? 0,
        title: c['title']?.toString() ?? c.toString(),
      );
    }
    if (c is String) {
      return Chapter(index: 0, startSec: 0, title: c);
    }
    return Chapter(index: 0, startSec: 0, title: c.toString());
  }).toList();
}

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
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              padding: const EdgeInsets.all(16.0),
              child: SummaryView(title: title, steps: steps),
            ),
            SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.ondemand_video_rounded,
                          color: Colors.blueGrey, size: 22),
                      SizedBox(width: 8),
                      Text('Vidéo',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  SizedBox(height: 8),
                  YouTubeEmbed(videoUrl: videoUrl),
                  SizedBox(height: 8),
                  VideoCard(title: title, videoUrl: videoUrl),
                ],
              ),
            ),
            if (chapters != null && chapters!.isNotEmpty) ...[
              SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                padding: const EdgeInsets.all(16.0),
                child: ChaptersView(
                  chapters: chaptersFromAny(chapters!),
                  videoUrl: videoUrl,
                ),
              ),
            ],
            if (transcript != null && transcript!.isNotEmpty) ...[
              SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notes_rounded,
                            color: Colors.deepPurple, size: 22),
                        SizedBox(width: 8),
                        Text('Transcript',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    SizedBox(height: 8),
                    ...transcript!.map((t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child:
                              Text(t, style: TextStyle(color: Colors.black87)),
                        )),
                  ],
                ),
              ),
            ],
            SizedBox(height: 24),
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
        ),
      ),
    );
  }
}
