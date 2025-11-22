import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/summary_view.dart';
import '../widgets/video_card.dart';
import '../models/base_search_result.dart';
import '../widgets/citations_view.dart';
import '../widgets/chapters_view.dart';
import '../providers/search_provider.dart';
import '../widgets/empty_state.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Résultats',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: ListView.separated(
          itemCount: 10, // exemple
          separatorBuilder: (_, __) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                leading: Icon(Icons.search, color: Colors.blue, size: 28),
                title: Text('Résultat ${index + 1}',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Détail du résultat',
                    style: TextStyle(color: Colors.grey[600])),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ResultMobileLayout extends StatelessWidget {
  const _ResultMobileLayout();

  @override
  Widget build(BuildContext context) {
    final result = _getResult(context);

    final isEmpty = result.title.isEmpty &&
        result.steps.isEmpty &&
        result.citations.isEmpty &&
        result.chapters.isEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Résultats'),
      ),
      body: isEmpty
          ? EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Aucun résultat',
              subtitle: 'Essayez une autre recherche ou demandez de l\'aide.',
              actionLabel: 'Demander de l\'aide',
              onAction: () {
                Navigator.of(context).pushNamed('/support');
              },
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(AdaptiveSpacing.medium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SummaryView(title: result.title, steps: result.steps),
                  if (result.keyTakeaways.isNotEmpty) ...[
                    SizedBox(height: AdaptiveSpacing.medium),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: EdgeInsets.all(AdaptiveSpacing.medium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Key Takeaways',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            ...result.keyTakeaways.map((t) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Text('• $t'),
                                ))
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (result.quiz.isNotEmpty) ...[
                    SizedBox(height: AdaptiveSpacing.medium),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: EdgeInsets.all(AdaptiveSpacing.medium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Quiz Yourself',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            ...result.quiz.map((q) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Text(
                                      'Q: ${q['question']}\nA: ${q['answer']}'),
                                ))
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (result.citations.isNotEmpty) ...[
                    SizedBox(height: AdaptiveSpacing.medium),
                    CitationsView(citations: result.citations),
                  ],
                  if (result.chapters.isNotEmpty) ...[
                    SizedBox(height: AdaptiveSpacing.medium),
                    ChaptersView(
                        chapters: result.chapters, videoUrl: result.videoUrl),
                  ],
                  SizedBox(height: AdaptiveSpacing.small),
                  VideoCard(title: result.title, videoUrl: result.videoUrl),
                  SizedBox(height: AdaptiveSpacing.medium),
                  if (result.source.isNotEmpty)
                    Center(
                      child: Text(
                        'Source: ${result.source}',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: SizeConfig.adaptiveFontSize(12),
                        ),
                      ),
                    ),
                  SizedBox(height: AdaptiveSpacing.large),
                  _BackButton(),
                ],
              ),
            ),
    );
  }
}

class _ResultTabletLayout extends StatelessWidget {
  const _ResultTabletLayout();

  @override
  Widget build(BuildContext context) {
    final result = _getResult(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Résultats'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: AdaptiveSpacing.maxContentWidth),
          child: Padding(
            padding: AdaptiveSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackButton(),
                SizedBox(height: AdaptiveSpacing.medium),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SummaryView(
                                title: result.title,
                                steps: result.steps,
                              ),
                              if (result.citations.isNotEmpty) ...[
                                SizedBox(height: AdaptiveSpacing.medium),
                                CitationsView(citations: result.citations),
                              ],
                              if (result.chapters.isNotEmpty) ...[
                                SizedBox(height: AdaptiveSpacing.medium),
                                ChaptersView(
                                    chapters: result.chapters,
                                    videoUrl: result.videoUrl),
                              ],
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: AdaptiveSpacing.medium),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            VideoCard(
                              title: result.title,
                              videoUrl: result.videoUrl,
                            ),
                            if (result.source.isNotEmpty) ...[
                              SizedBox(height: AdaptiveSpacing.small),
                              Text(
                                'Source: ${result.source}',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: SizeConfig.adaptiveFontSize(14),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultDesktopLayout extends StatelessWidget {
  const _ResultDesktopLayout();

  @override
  Widget build(BuildContext context) {
    final result = _getResult(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Résultats'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: AdaptiveSpacing.maxContentWidth),
          child: Padding(
            padding: AdaptiveSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackButton(),
                SizedBox(height: AdaptiveSpacing.large),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SummaryView(
                                title: result.title,
                                steps: result.steps,
                              ),
                              if (result.citations.isNotEmpty) ...[
                                SizedBox(height: AdaptiveSpacing.medium),
                                CitationsView(citations: result.citations),
                              ],
                              if (result.chapters.isNotEmpty) ...[
                                SizedBox(height: AdaptiveSpacing.medium),
                                ChaptersView(
                                    chapters: result.chapters,
                                    videoUrl: result.videoUrl),
                              ],
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: AdaptiveSpacing.large),
                      Expanded(
                        child: Column(
                          children: [
                            VideoCard(
                              title: result.title,
                              videoUrl: result.videoUrl,
                            ),
                            if (result.source.isNotEmpty) ...[
                              SizedBox(height: AdaptiveSpacing.medium),
                              Text(
                                'Source: ${result.source}',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: SizeConfig.adaptiveFontSize(14),
                                ),
                              ),
                            ],
                            // Space for additional desktop features
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(180, 44),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, size: 20),
        label: const Text('← Nouvelle recherche'),
      ),
    );
  }
}

BaseSearchResult _getResult(BuildContext context) {
  final arg = ModalRoute.of(context)!.settings.arguments;
  BaseSearchResult? res;

  if (arg is BaseSearchResult) {
    res = arg;
  } else if (arg is Map<String, dynamic>) {
    res = BaseSearchResult.fromMap(arg);
  } else {
    res = context.watch<SearchProvider>().result;
  }

  return BaseSearchResult(
    title: res?.title ?? 'Résultat',
    steps: res?.steps ?? <String>[],
    videoUrl: res?.videoUrl ?? '',
    source: res?.source ?? '',
    citations: res?.citations ?? const [],
    chapters: res?.chapters ?? const [],
  );
}
