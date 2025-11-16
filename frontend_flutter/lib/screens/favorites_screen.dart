import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
import '../screens/lesson_detail_screen.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/empty_state.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Favoris')),
      body: Consumer2<LessonsProvider, HistoryFavoritesProvider>(
        builder: (context, lp, favs, _) {
          final lessonFavs = lp.lessons.where((l) => l.favorite).toList();
          if (lessonFavs.isNotEmpty) {
            // Show backend-persisted favorites (lessons)
            return ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(AdaptiveSpacing.large),
              itemBuilder: (context, index) {
                final l = lessonFavs[index];
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AdaptiveSpacing.large,
                      vertical: AdaptiveSpacing.medium,
                    ),
                    leading:
                        const Icon(Icons.star, color: Colors.amber, size: 28),
                    title: Text(
                      l.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    subtitle: Text(
                      l.videoUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonDetailScreen(lesson: l),
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: lessonFavs.length,
            );
          }

          // Fallback to legacy local favorites
          final items = favs.favorites;
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.star_border_rounded,
              title: 'Aucun favori',
              subtitle:
                  'Ajoutez des vidéos à conserver pour les retrouver rapidement.',
              actionLabel: 'Rechercher des leçons',
              onAction: () {
                Navigator.of(context).pushNamed('/search');
              },
            );
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(AdaptiveSpacing.medium),
            itemBuilder: (context, index) {
              final f = items[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AdaptiveSpacing.small,
                    vertical: AdaptiveSpacing.tiny,
                  ),
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: Text(f.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    f.channel ?? f.videoUrl ?? f.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // trailing: IconButton(
                  //   tooltip: 'Retirer',
                  //   icon: const Icon(Icons.close_rounded),
                  //   color: scheme.error,
                  //   onPressed: () => favs.toggleFavorite(
                  //     videoId: f.id,
                  //     title: f.title,
                  //     channel: f.channel,
                  //     videoUrl: f.videoUrl,
                  //   ),
                  // ),
                  onTap: () => _openUrl(f.videoUrl ?? ''),
                ),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: items.length,
          );
        },
      ),
    );
  }
}
