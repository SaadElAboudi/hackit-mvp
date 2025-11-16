import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/lessons_provider.dart';
import '../models/lesson.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/empty_state.dart';
import 'lesson_detail_screen.dart';

class LessonsScreen extends StatelessWidget {
  const LessonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leçons'),
      ),
      body: const _LessonsBody(),
    );
  }
}

class _LessonsBody extends StatelessWidget {
  const _LessonsBody();

  @override
  Widget build(BuildContext context) {
    // Removed unused googleAuth variable
    return Consumer<LessonsProvider>(
      builder: (context, lp, _) {
        // Removed unused debugUserId/debugUser
        return Column(
          children: [
            // DEBUG: Affichage du userId et du token Google
            // Removed all debug info for professional UI
            Expanded(
              child: Builder(
                builder: (context) {
                  if (lp.loading && lp.lessons.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (lp.error != null && lp.lessons.isEmpty) {
                    return EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Impossible de charger les leçons.',
                      subtitle:
                          'Veuillez réessayer plus tard ou demander de l\'aide.',
                      actionLabel: 'Réessayer',
                      onAction: () {
                        // Retry callback: reload lessons
                        lp.fetchLessons(force: true);
                      },
                    );
                  }
                  if (lp.lessons.isEmpty) {
                    return EmptyState(
                      icon: Icons.school_outlined,
                      title: 'Aucune leçon pour le moment',
                      subtitle:
                          'Générez une leçon depuis le chat, elle apparaîtra ici.',
                      actionLabel: 'Demander de l\'aide',
                      onAction: () {
                        // Request help callback: open support or help page
                        Navigator.of(context).pushNamed('/support');
                      },
                    );
                  }
                  // Removed RefreshIndicator, use plain ListView
                  return ListView.separated(
                    padding: EdgeInsets.symmetric(
                      horizontal: AdaptiveSpacing.medium,
                      vertical: AdaptiveSpacing.small,
                    ),
                    itemBuilder: (context, index) {
                      final l = lp.lessons[index];
                      return _LessonTile(lesson: l);
                    },
                    separatorBuilder: (_, __) =>
                        SizedBox(height: AdaptiveSpacing.tiny),
                    itemCount: lp.lessons.length,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LessonTile extends StatelessWidget {
  final Lesson lesson;
  const _LessonTile({required this.lesson});

  @override
  Widget build(BuildContext context) {
    final lp = context.read<LessonsProvider>();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: AdaptiveSpacing.large,
              vertical: AdaptiveSpacing.medium,
            ),
            title: Text(
              lesson.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _subtitle(lesson),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (lesson.progress > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: LinearProgressIndicator(
                      value: lesson.progress / 100.0,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      color: Colors.blueAccent,
                    ),
                  ),
                if (lesson.reminder != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Rappel: ${lesson.reminder}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: lesson.favorite
                      ? 'Retirer des favoris'
                      : 'Ajouter aux favoris',
                  icon: Icon(
                    lesson.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: lesson.favorite ? Colors.amber : Colors.grey,
                    size: 28,
                  ),
                  onPressed: () => lp.toggleFavorite(lesson.id),
                ),
                IconButton(
                  tooltip: 'Supprimer la leçon',
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 26),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Supprimer la leçon ?'),
                        content: const Text('Cette action est irréversible.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Supprimer'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await lp.deleteLesson(lesson.id);
                    }
                  },
                ),
              ],
            ),
            onTap: () async {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LessonDetailScreen(lesson: lesson),
                  ),
                );
                await lp.recordView(lesson.id);
              });
            },
          ),
          if (lesson.guestPrompt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.yellow.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lesson.guestPrompt!,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(Lesson l) {
    final created = l.createdAt;
    final views = l.views;
    final steps = l.steps.length;
    final date =
        '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}';
    return '$steps étapes • $views vues • $date';
  }
}
