import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
import 'lesson_detail_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<HistoryFavoritesProvider>().favorites;
    final history = context.watch<HistoryFavoritesProvider>().history;
    final lessons = context.watch<LessonsProvider>().lessons;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pipeline'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SectionHeader(
            title: 'Favoris',
            count: favorites.length,
            emptyLabel: 'Aucun favori pour le moment.',
          ),
          ...favorites.take(8).map((item) => Card(
                child: ListTile(
                  leading:
                      Icon(Icons.star_rounded, color: Colors.amber.shade600),
                  title: Text(item.title.isEmpty ? 'Sans titre' : item.title),
                  subtitle: Text(item.videoUrl ?? item.id,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                    onPressed: () {
                      context.read<HistoryFavoritesProvider>().toggleFavorite(
                            videoId: item.id,
                            title: item.title,
                            videoUrl: item.videoUrl,
                          );
                    },
                  ),
                ),
              )),
          const SizedBox(height: 12),
          _SectionHeader(
            title: 'Historique',
            count: history.length,
            emptyLabel: 'Aucun historique.',
          ),
          ...history.take(8).map((item) => Card(
                child: ListTile(
                  leading: Icon(Icons.history_rounded, color: scheme.primary),
                  title: Text((item.title?.isNotEmpty ?? false)
                      ? item.title!
                      : item.query),
                  subtitle: Text(item.query,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                    onPressed: () => context
                        .read<HistoryFavoritesProvider>()
                        .removeHistory(item.id),
                  ),
                ),
              )),
          const SizedBox(height: 12),
          _SectionHeader(
            title: 'Livrables sauvegardés',
            count: lessons.length,
            emptyLabel: 'Aucun livrable sauvegardé.',
          ),
          ...lessons.take(8).map((lesson) => Card(
                child: ListTile(
                  leading:
                      Icon(Icons.menu_book_rounded, color: scheme.tertiary),
                  title: Text(lesson.title),
                  subtitle: Text(lesson.videoUrl,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonDetailScreen(lesson: lesson),
                      ),
                    );
                  },
                ),
              )),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final String emptyLabel;
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const Spacer(),
          if (count == 0)
            Text(
              emptyLabel,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
