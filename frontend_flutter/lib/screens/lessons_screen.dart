import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/lessons_provider.dart';
import '../models/lesson.dart';
import '../core/responsive/adaptive_spacing.dart';
import 'lesson_detail_screen.dart';

class LessonsScreen extends StatelessWidget {
  const LessonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leçons'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<LessonsProvider>().refresh(),
          )
        ],
      ),
      body: const _LessonsBody(),
    );
  }
}

class _LessonsBody extends StatelessWidget {
  const _LessonsBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<LessonsProvider>(
      builder: (context, lp, _) {
        if (lp.loading && lp.lessons.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (lp.error != null && lp.lessons.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(AdaptiveSpacing.large),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: Colors.redAccent),
                  SizedBox(height: AdaptiveSpacing.small),
                  Text(lp.error!, textAlign: TextAlign.center),
                  SizedBox(height: AdaptiveSpacing.small),
                  FilledButton.icon(
                    onPressed: () => lp.refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Réessayer'),
                  )
                ],
              ),
            ),
          );
        }
        if (lp.lessons.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(AdaptiveSpacing.large),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.school_outlined, size: 56),
                  SizedBox(height: AdaptiveSpacing.small),
                  const Text('Aucune leçon pour le moment'),
                  SizedBox(height: AdaptiveSpacing.small),
                  const Text(
                      'Générez une leçon depuis le chat, elle apparaîtra ici.'),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => lp.refresh(),
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: AdaptiveSpacing.medium,
              vertical: AdaptiveSpacing.small,
            ),
            itemBuilder: (context, index) {
              final l = lp.lessons[index];
              return _LessonTile(lesson: l);
            },
            separatorBuilder: (_, __) => SizedBox(height: AdaptiveSpacing.tiny),
            itemCount: lp.lessons.length,
          ),
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
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AdaptiveSpacing.medium,
          vertical: AdaptiveSpacing.small,
        ),
        title: Text(lesson.title),
        subtitle: Text(_subtitle(lesson)),
        trailing: IconButton(
          tooltip:
              lesson.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
          icon: Icon(
            lesson.favorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: lesson.favorite ? Colors.amber : null,
          ),
          onPressed: () => lp.toggleFavorite(lesson.id),
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LessonDetailScreen(lesson: lesson),
            ),
          );
          // Record a view on return (user visited details)
          // Alternatively could be done on push.
          await lp.recordView(lesson.id);
        },
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
