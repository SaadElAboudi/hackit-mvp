import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
// ...existing code...
import '../widgets/empty_state.dart';
import '../core/responsive/adaptive_spacing.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 3,
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_rounded,
                  color: Color(0xFF00C48C), size: 28),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Favoris',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Color(0xFF222B45),
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Color(0x22000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 38,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Color(0xFF00C48C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [IconButton(icon: Icon(Icons.favorite), onPressed: () {})],
        ),
      ),
      body: _FavoritesList(),
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
                        await Provider.of<LessonsProvider>(context,
                                listen: false)
                            .toggleFavorite(l.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Retiré des favoris'),
                              backgroundColor: Colors.green),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
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
            'Ajoutez des vidéos à conserver pour les retrouver rapidement.',
        actionLabel: 'Rechercher des leçons',
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Retiré des favoris'),
                            backgroundColor: Colors.green),
                      );
                    } catch (err) {
                      ScaffoldMessenger.of(context).showSnackBar(
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
