import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/history_favorites_provider.dart';
import '../core/responsive/adaptive_spacing.dart';

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
      body: Consumer<HistoryFavoritesProvider>(
        builder: (context, favs, _) {
          final items = favs.favorites;
          if (items.isEmpty) {
            return const Center(child: Text('Aucun favori'));
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(AdaptiveSpacing.medium),
            itemBuilder: (context, index) {
              final f = items[index];
              return ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AdaptiveSpacing.small,
                  vertical: AdaptiveSpacing.tiny,
                ),
                leading: const Icon(Icons.star, color: Colors.amber),
                title:
                    Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  f.channel ?? f.videoUrl ?? f.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close_rounded),
                  color: scheme.error,
                  onPressed: () => favs.toggleFavorite(
                    videoId: f.id,
                    title: f.title,
                    channel: f.channel,
                    videoUrl: f.videoUrl,
                  ),
                ),
                onTap: () => _openUrl(f.videoUrl ?? ''),
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
