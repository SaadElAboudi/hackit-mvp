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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        title: const Text(
          'Bibliothèque',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF222B45),
          ),
        ),
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
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: Text(item.title.isEmpty ? 'Sans titre' : item.title),
                  subtitle: Text(item.videoUrl ?? item.id),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
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
                  leading: const Icon(Icons.history_rounded, color: Colors.blueAccent),
                  title: Text((item.title?.isNotEmpty ?? false) ? item.title! : item.query),
                  subtitle: Text(item.query),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => context.read<HistoryFavoritesProvider>().removeHistory(item.id),
                  ),
                ),
              )),
          const SizedBox(height: 12),
          _SectionHeader(
            title: 'Leçons sauvegardées',
            count: lessons.length,
            emptyLabel: 'Aucune leçon sauvegardée.',
          ),
          ...lessons.take(8).map((lesson) => Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_rounded, color: Color(0xFF00C48C)),
                  title: Text(lesson.title),
                  subtitle: Text(lesson.videoUrl),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF3F7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count'),
          ),
          const Spacer(),
          if (count == 0)
            Text(
              emptyLabel,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
