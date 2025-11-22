import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/lessons_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_scaffold.dart';
import '../core/responsive/adaptive_spacing.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Historique',
      actions: [IconButton(icon: Icon(Icons.history), onPressed: () {})],
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
      padding: AdaptiveSpacing.screenPadding,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(height: 12),
        itemBuilder: (context, index) {
          final e = items[index];
          final title =
              (e.title == null || e.title!.isEmpty) ? e.query : e.title!;
          final subtitle = e.query;
          return Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            margin: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              leading: Icon(Icons.history, size: 26, color: Colors.blueGrey),
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
