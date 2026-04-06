// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lessons_provider.dart';
// ...existing code...
import '../services/pdf_export_service.dart';
import '../widgets/action_tracker_button.dart';
import '../widgets/challenge_section.dart';
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
          // Vidéo de référence: expandable to avoid cluttering the plan view
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
          // Devil's Advocate: challenge the plan in-place
          ChallengeSection(
            deliverable: (() {
              final rts = deliveryPlan?['readyToSend'];
              if (rts is String && rts.trim().isNotEmpty) return rts.trim();
              return steps.join('\n');
            })(),
            query: title,
            mode: deliveryMode ?? 'produire',
          ),
          SizedBox(height: 8),
          // Compact action row: export PDF + save
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ActionTrackerButton(
                  deliverableTitle: title,
                  deliveryPlan: deliveryPlan,
                  steps: steps,
                ),
                _ExportPdfButton(
                  title: title,
                  steps: steps,
                  deliveryMode: deliveryMode,
                  deliveryPlan: deliveryPlan,
                  source: source,
                ),
                if (saveError != null &&
                    saveError.trim().isNotEmpty &&
                    !alreadySaved)
                  Expanded(
                    child: Text(
                      saveError,
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    ),
                  ),
                Tooltip(
                  message: alreadySaved
                      ? 'Enregistré dans le pipeline'
                      : 'Enregistrer dans le pipeline',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: lessons.loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            alreadySaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_add_outlined,
                            size: 18,
                          ),
                    label: Text(
                      alreadySaved ? 'Sauvegardé' : 'Sauvegarder',
                      style: const TextStyle(fontSize: 13),
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
                                      "Échec de l'enregistrement"),
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

class _ExportPdfButton extends StatefulWidget {
  final String title;
  final List<String> steps;
  final String? deliveryMode;
  final Map<String, dynamic>? deliveryPlan;
  final String? source;

  const _ExportPdfButton({
    required this.title,
    required this.steps,
    required this.deliveryMode,
    required this.deliveryPlan,
    required this.source,
  });

  @override
  State<_ExportPdfButton> createState() => _ExportPdfButtonState();
}

class _ExportPdfButtonState extends State<_ExportPdfButton> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await PdfExportService.exportAndShare(
        title: widget.title,
        steps: widget.steps,
        deliveryMode: widget.deliveryMode,
        deliveryPlan: widget.deliveryPlan,
        source: widget.source,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export PDF échoué : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Exporter en PDF',
      child: TextButton.icon(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: _exporting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: const Text('Export PDF', style: TextStyle(fontSize: 13)),
        onPressed: _exporting ? null : _export,
      ),
    );
  }
}
