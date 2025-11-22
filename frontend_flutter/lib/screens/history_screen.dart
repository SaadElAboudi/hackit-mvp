import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
import '../widgets/empty_state.dart';
// ...existing code...
// ...existing code...

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

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
              const Icon(Icons.history_rounded,
                  color: Color(0xFF00C48C), size: 28),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Historique',
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
          actions: [IconButton(icon: Icon(Icons.history), onPressed: () {})],
        ),
      ),
      body: _HistoryList(),
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
                      await Provider.of<HistoryFavoritesProvider>(context,
                              listen: false)
                          .removeHistory(e.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Entrée supprimée'),
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
                // Navigation possible vers le détail ou recherche associée
              },
            ),
          );
        },
      ),
    );
  }
}
