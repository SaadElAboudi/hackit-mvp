import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
// ...existing code...
import '../widgets/empty_state.dart';
import '../widgets/app_scaffold.dart';
// ...existing code...

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Favoris',
      subtitle: 'Tes contenus preferes a portee de main',
      leadingIcon: Icons.favorite_rounded,
      child: _FavoritesList(),
    );
  }
}

class _FavoritesList extends StatelessWidget {
  const _FavoritesList();

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LessonsProvider>(context);
    final favs = Provider.of<HistoryFavoritesProvider>(context);
    final lessonFavs = lp.lessons.where((l) => l.favorite).toList();
    if (lessonFavs.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ListView.separated(
          itemCount: lessonFavs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final l = lessonFavs[index];
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                leading: const Icon(Icons.star_rounded,
                    color: Colors.amber, size: 32),
                title: Text(
                  l.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 19),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: l.videoUrl.isNotEmpty
                    ? Text(l.videoUrl,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14))
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  tooltip: 'Supprimer',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final lessonsProvider =
                        Provider.of<LessonsProvider>(context, listen: false);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Retirer des favoris'),
                        content: const Text(
                            'Voulez-vous retirer cette leçon des favoris ?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Retirer',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await lessonsProvider.toggleFavorite(l.id);
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Retiré des favoris'),
                              backgroundColor: Colors.green),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Erreur : $e'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
                onTap: () {
                  Navigator.of(context)
                      .pushNamed('/lesson_detail', arguments: l);
                },
              ),
            );
          },
        ),
      );
    }
    final items = favs.favorites;
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.star_border_rounded,
        title: 'Aucun favori',
        subtitle:
            'Ajoutez des ressources a conserver pour les retrouver rapidement.',
        actionLabel: 'Generer un livrable',
        onAction: () {
          Navigator.of(context).pushNamed('/search');
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final e = items[index];
          final title = e.title;
          final subtitle = e.videoUrl ?? '';
          return Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              leading: const Icon(Icons.favorite_rounded,
                  color: Colors.redAccent, size: 32),
              title: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 19)),
              subtitle: subtitle.isNotEmpty
                  ? Text(subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 14))
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                tooltip: 'Supprimer',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Retirer des favoris'),
                      content: const Text(
                          'Voulez-vous retirer cette vidéo des favoris ?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Annuler'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Retirer',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      await favs.toggleFavorite(
                        videoId: e.id,
                        title: e.title,
                        videoUrl: e.videoUrl,
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text('Retiré des favoris'),
                            backgroundColor: Colors.green),
                      );
                    } catch (err) {
                      messenger.showSnackBar(
                        SnackBar(
                            content: Text('Erreur : $err'),
                            backgroundColor: Colors.red),
                      );
                    }
                  }
                },
              ),
              onTap: () {
                Navigator.of(context).pushNamed('/lesson_detail', arguments: e);
              },
            ),
          );
        },
      ),
    );
  }
}
