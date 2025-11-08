import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../widgets/summary_view.dart';
import '../widgets/video_card.dart';
import '../models/base_search_result.dart';
import '../providers/search_provider.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig.init(context);
    return const ResponsiveLayout(
      mobile: _ResultMobileLayout(),
      tablet: _ResultTabletLayout(),
      desktop: _ResultDesktopLayout(),
    );
  }
}

class _ResultMobileLayout extends StatelessWidget {
  const _ResultMobileLayout();

  @override
  Widget build(BuildContext context) {
    final result = _getResult(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Résultats')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(AdaptiveSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SummaryView(title: result.title, steps: result.steps),
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
      appBar: AppBar(title: const Text('Résultats')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AdaptiveSpacing.maxContentWidth),
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
                        child: SummaryView(
                          title: result.title,
                          steps: result.steps,
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
      appBar: AppBar(title: const Text('Résultats')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AdaptiveSpacing.maxContentWidth),
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
                        child: SummaryView(
                          title: result.title,
                          steps: result.steps,
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
    return ElevatedButton.icon(
      onPressed: () => Navigator.pop(context),
      icon: const Icon(Icons.arrow_back),
      label: Text(
        '← Nouvelle recherche',
        style: TextStyle(
          fontSize: SizeConfig.adaptiveFontSize(14),
        ),
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
  );
}
