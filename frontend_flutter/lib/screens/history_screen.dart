import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_scaffold.dart';
// ...existing code...
// ...existing code...

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Historique',
      subtitle: 'Retrouve rapidement tes derniers parcours',
      leadingIcon: Icons.history_rounded,
      child: _HistoryList(),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context) {
    final historyProvider = Provider.of<HistoryFavoritesProvider>(context);
    final lessonsProvider = Provider.of<LessonsProvider>(context);
    final items = historyProvider.history;
    final recentLessons = [...lessonsProvider.lessons]
      ..removeWhere((l) => l.lastViewedAt == null)
      ..sort((a, b) => (b.lastViewedAt ?? DateTime(0))
          .compareTo(a.lastViewedAt ?? DateTime(0)));
    if (items.isEmpty && recentLessons.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: 'Aucun historique',
        subtitle: 'Vos recherches et leçons récentes apparaîtront ici.',
        actionLabel: 'Demander de l\'aide',
        onAction: () {
          Navigator.of(context).pushNamed('/support');
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
          final title =
              (e.title == null || e.title!.isEmpty) ? e.query : e.title!;
          final subtitle = e.query;
          return Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              leading: const Icon(Icons.history_rounded,
                  size: 32, color: Colors.blueAccent),
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
                  final history =
                      Provider.of<HistoryFavoritesProvider>(context, listen: false);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supprimer historique'),
                      content:
                          const Text('Voulez-vous supprimer cette entrée ?'),
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
                      await history.removeHistory(e.id);
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text('Entrée supprimée'),
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
                // Navigation possible vers le détail ou recherche associée
              },
            ),
          );
        },
      ),
    );
  }
}
