// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/challenge_section.dart';
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
  final String? source;
  final String? deliveryMode;
  final Map<String, dynamic>? deliveryPlan;
  final List<String>? transcript;
  final List<String>? chapters;
  const LessonView({
    super.key,
    required this.title,
    required this.steps,
    required this.videoUrl,
    this.source,
    this.deliveryMode,
    this.deliveryPlan,
    this.transcript,
    this.chapters,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Steps summary
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.25)),
            ),
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.bolt_rounded,
                        color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: scheme.onSurface),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copier',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: '$title\n\n${steps.join('\n')}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Copié dans le presse-papiers')),
                        );
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  ...steps.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e.key + 1}. ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.primary,
                                    fontSize: 14)),
                            Expanded(
                              child: Text(e.value,
                                  style: const TextStyle(fontSize: 14)),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          // Video reference: expandable
          if (videoUrl.startsWith('http'))
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.25)),
              ),
              color: scheme.surfaceContainerLow,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: Icon(Icons.ondemand_video_rounded,
                    color: scheme.primary, size: 20),
                title: Text('Vidéo de référence',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: scheme.onSurface)),
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  YouTubeEmbed(videoUrl: videoUrl),
                ],
              ),
            ),
          if (chapters != null && chapters!.isNotEmpty) ...[
            SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.25)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: ChaptersView(
                chapters: chaptersFromAny(chapters!),
                videoUrl: videoUrl,
              ),
            ),
          ],
          if (transcript != null && transcript!.isNotEmpty) ...[
            SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.25)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notes_rounded,
                          color: scheme.secondary, size: 20),
                      SizedBox(width: 8),
                      Text('Transcript',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: scheme.onSurface)),
                    ],
                  ),
                  SizedBox(height: 8),
                  ...transcript!.map((t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(t,
                            style: TextStyle(
                                color:
                                    scheme.onSurface.withValues(alpha: 0.8))),
                      )),
                ],
              ),
            ),
          ],
          SizedBox(height: 12),
          ChallengeSection(
            deliverable: (() {
              final rts = deliveryPlan?['readyToSend'];
              if (rts is String && rts.trim().isNotEmpty) return rts.trim();
              return steps.join('\n');
            })(),
            query: title,
            mode: deliveryMode ?? 'produire',
          ),
        ],
      ),
    );
  }
}
