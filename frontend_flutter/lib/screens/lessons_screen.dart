import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/lessons_provider.dart';
import '../models/lesson.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_scaffold.dart';
import 'lesson_detail_screen.dart';

class LessonsScreen extends StatelessWidget {
  const LessonsScreen({super.key});

  String _subtitle(Lesson l) {
    final created = l.createdAt;
    final views = l.views;
    final createdStr =
        'Créé le ${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}';
    final viewsStr = ' • $views vues';
    return '$createdStr$viewsStr';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Lecons',
      subtitle: 'Toutes tes lecons sauvegardees',
      leadingIcon: Icons.menu_book_rounded,
      child: Consumer<LessonsProvider>(
        builder: (context, lp, _) {
          final lessons = lp.lessons;
          if (lessons.isEmpty) {
            return const EmptyState(
              icon: Icons.menu_book,
              title: 'Aucune leçon',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: lessons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final lesson = lessons[index];
              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: ListTile(
                  title: Text(
                    lesson.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: Text(_subtitle(lesson)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Supprimer',
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final lessonsProvider =
                          Provider.of<LessonsProvider>(context, listen: false);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Supprimer la leçon'),
                          content: const Text(
                              'Voulez-vous vraiment supprimer cette leçon ?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Annuler'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Supprimer',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await lessonsProvider.deleteLesson(lesson.id);
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('Leçon supprimée'),
                                backgroundColor: Colors.green),
                          );
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                                content:
                                    Text('Erreur lors de la suppression : $e'),
                                backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonDetailScreen(lesson: lesson),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
