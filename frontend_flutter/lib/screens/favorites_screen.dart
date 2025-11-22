import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/empty_state.dart';
import '../core/responsive/adaptive_spacing.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Favoris',
      actions: [IconButton(icon: Icon(Icons.favorite), onPressed: () {})],
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
        padding: AdaptiveSpacing.screenPadding,
        child: ListView.separated(
          itemCount: lessonFavs.length,
          separatorBuilder: (_, __) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            final l = lessonFavs[index];
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              margin: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: ListTile(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                leading: Icon(Icons.star, color: Colors.amber, size: 28),
                title: Text(l.title,
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle:
                    Text(l.videoUrl, style: TextStyle(color: Colors.grey[600])),
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
      padding: AdaptiveSpacing.screenPadding,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(height: 12),
        itemBuilder: (context, index) {
          final e = items[index];
          final title = e.title;
          final subtitle = e.videoUrl ?? '';
          return Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            margin: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              leading: Icon(Icons.favorite, color: Colors.redAccent, size: 26),
              title: Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle:
                  Text(subtitle, style: TextStyle(color: Colors.grey[600])),
            ),
          );
        },
      ),
    );
  }
}
