// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lessons_provider.dart';
// ...existing code...
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
    final lessons = context.watch<LessonsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final alreadySaved =
        lessons.lessons.any((l) => l.title == title && l.videoUrl == videoUrl);
    final canSave = title.trim().length >= 2 &&
        steps.isNotEmpty &&
        videoUrl.startsWith('http');
    final saveError = lessons.error;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SummaryView(
            title: title,
            steps: steps,
            source: source,
            deliveryMode: deliveryMode,
            deliveryPlan: deliveryPlan,
          ),
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
                    Icon(Icons.ondemand_video_rounded,
                        color: scheme.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Vidéo',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: scheme.onSurface)),
                  ],
                ),
                SizedBox(height: 10),
                YouTubeEmbed(videoUrl: videoUrl),
                SizedBox(height: 8),
                VideoCard(title: title, videoUrl: videoUrl),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bookmark_add_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'Sauvegarde',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: scheme.onSurface),
                    ),
                    const Spacer(),
                    if (alreadySaved)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Enregistrée',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  alreadySaved
                      ? 'Ce livrable est déjà dans ton pipeline.'
                      : 'Ajoute cette réponse à ton pipeline pour la retrouver et la réutiliser rapidement.',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                if (!canSave && !alreadySaved) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Impossible d\'enregistrer: lien vidéo invalide.',
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ],
                if (saveError != null &&
                    saveError.trim().isNotEmpty &&
                    !alreadySaved) ...[
                  const SizedBox(height: 10),
                  Text(
                    saveError,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: lessons.loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            alreadySaved
                                ? Icons.check_rounded
                                : Icons.bookmark_add_rounded,
                          ),
                    label: Text(
                      alreadySaved
                          ? 'Livrable enregistré'
                          : (lessons.loading
                              ? 'Enregistrement...'
                              : 'Enregistrer le livrable'),
                    ),
                    onPressed: (!alreadySaved && canSave && !lessons.loading)
                        ? () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final created = await lessons.saveFromChat(
                              title: title,
                              steps: steps,
                              videoUrl: videoUrl,
                            );
                            if (created != null) {
                              messenger.showSnackBar(
                                const SnackBar(
                                    content: Text('Livrable enregistré.')),
                              );
                            } else {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(lessons.error ??
                                      'Échec de l\'enregistrement'),
                                ),
                              );
                            }
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
