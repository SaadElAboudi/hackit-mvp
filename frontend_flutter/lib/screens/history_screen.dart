import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_favorites_provider.dart';
import '../providers/search_provider.dart';
import '../providers/lessons_provider.dart';
import '../screens/lesson_detail_screen.dart';
import '../core/responsive/adaptive_spacing.dart';
import 'home_screen.dart';
import '../widgets/empty_state.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WillPopScope(
      onWillPop: () async {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        });
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Historique'),
        ),
        body: Consumer3<HistoryFavoritesProvider, SearchProvider,
            LessonsProvider>(
          builder: (context, hist, search, lessons, _) {
            final items = hist.history;
            final recentLessons = [...lessons.lessons]
              ..removeWhere((l) => l.lastViewedAt == null)
              ..sort((a, b) => b.lastViewedAt!.compareTo(a.lastViewedAt!));
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
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(AdaptiveSpacing.medium),
              children: [
                // Legacy local search history
                if (items.isNotEmpty) ...[
                  ...List.generate(items.length, (index) {
                    final e = items[index];
                    final title = (e.title == null || e.title!.isEmpty)
                        ? e.query
                        : e.title!;
                    final subtitle = e.query;
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
                        leading: const Icon(Icons.history, size: 26),
                        title: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }),
                  SizedBox(height: AdaptiveSpacing.medium),
                ],

                // Recent viewed lessons
                if (recentLessons.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(
                        left: AdaptiveSpacing.small,
                        bottom: AdaptiveSpacing.small),
                    child: const Text(
                      'Vos leçons vues récemment',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ...recentLessons.map((l) => Padding(
                        padding: EdgeInsets.only(bottom: AdaptiveSpacing.tiny),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: AdaptiveSpacing.small,
                              vertical: AdaptiveSpacing.tiny,
                            ),
                            leading: const Icon(Icons.school_rounded,
                                color: Colors.blueGrey),
                            title: Text(l.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              l.videoUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text('${l.views} vues'),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => LessonDetailScreen(lesson: l),
                                ),
                              );
                              await lessons.recordView(l.id);
                            },
                          ),
                        ),
                      )),
                ],
              ],
            );
          },
        ),
      ),
    ); // Fin WillPopScope
  }
}
