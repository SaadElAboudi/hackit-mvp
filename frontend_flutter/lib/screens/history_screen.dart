import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/search_provider.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/empty_state.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
      ),
      body: Consumer2<HistoryFavoritesProvider, SearchProvider>(
        builder: (context, hist, search, _) {
          final items = hist.history;
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.history_rounded,
              title: 'Aucun historique',
              subtitle:
                  'Vos recherches récentes apparaîtront ici pour les relancer en un tap.',
              actionLabel: 'Rechercher une vidéo',
              onAction: () => Navigator.of(context).pop(),
            );
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(AdaptiveSpacing.medium),
            itemBuilder: (context, index) {
              final e = items[index];
              final title =
                  (e.title == null || e.title!.isEmpty) ? e.query : e.title!;
              final subtitle = e.query;
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
                  title:
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  leading: const Icon(Icons.history),
                  trailing: IconButton(
                    tooltip: 'Relancer',
                    icon: const Icon(Icons.play_arrow_rounded),
                    color: scheme.primary,
                    onPressed: search.loading
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            // Delay the call to ensure pop completes before starting search
                            Future.microtask(
                                () => search.searchStreaming(e.query));
                          },
                  ),
                  onTap: search.loading
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          Future.microtask(
                              () => search.searchStreaming(e.query));
                        },
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
