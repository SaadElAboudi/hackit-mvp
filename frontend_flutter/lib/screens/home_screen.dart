import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../providers/search_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/summary_view.dart';
import '../widgets/video_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig.init(context);
    return const ResponsiveLayout(
      mobile: _HomeMobileLayout(),
      tablet: _HomeTabletLayout(),
      desktop: _HomeDesktopLayout(),
    );
  }
}

class _HomeMobileLayout extends StatelessWidget {
  const _HomeMobileLayout();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (provider.result != null &&
          !provider.loading &&
          provider.error == null) {
        Navigator.pushNamed(context, '/result', arguments: provider.result);
      }
    });
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Hackit MVP')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.15),
              scheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  vertical: AdaptiveSpacing.medium,
                  horizontal: AdaptiveSpacing.large,
                ),
                child: Text(
                  'Posez votre question',
                  style: TextStyle(
                    fontSize: SizeConfig.adaptiveFontSize(18),
                  ),
                ),
              ),
              ChatInput(
                onSearch: (query) => provider.search(query),
                disabled: provider.loading,
              ),
              if (provider.loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator())),
              if (provider.error != null)
                Padding(
                  padding: EdgeInsets.all(AdaptiveSpacing.medium),
                  child: Text(
                    '❌ ${provider.error}',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: SizeConfig.adaptiveFontSize(14),
                    ),
                  ),
                ),
              if (provider.result != null && !provider.loading)
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(AdaptiveSpacing.medium),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SummaryView(
                          title: provider.result!.title,
                          steps: provider.result!.steps,
                        ),
                        SizedBox(height: AdaptiveSpacing.small),
                        VideoCard(
                          title: provider.result!.title,
                          videoUrl: provider.result!.videoUrl,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTabletLayout extends StatelessWidget {
  const _HomeTabletLayout();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Hackit MVP')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.12),
              scheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AdaptiveSpacing.maxContentWidth,
              ),
              child: Padding(
                padding: AdaptiveSpacing.screenPadding,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Posez votre question',
                                style: TextStyle(
                                  fontSize: SizeConfig.adaptiveFontSize(20),
                                ),
                              ),
                              SizedBox(height: AdaptiveSpacing.medium),
                              ChatInput(
                                onSearch: (query) => provider.search(query),
                                disabled: provider.loading,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (provider.loading)
                      const Expanded(
                          child: Center(child: CircularProgressIndicator())),
                    if (provider.error != null)
                      Padding(
                        padding: EdgeInsets.all(AdaptiveSpacing.medium),
                        child: Text(
                          '❌ ${provider.error}',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: SizeConfig.adaptiveFontSize(16),
                          ),
                        ),
                      ),
                    if (provider.result != null && !provider.loading)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: SummaryView(
                                title: provider.result!.title,
                                steps: provider.result!.steps,
                              ),
                            ),
                            SizedBox(width: AdaptiveSpacing.medium),
                            Expanded(
                              flex: 2,
                              child: VideoCard(
                                title: provider.result!.title,
                                videoUrl: provider.result!.videoUrl,
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
        ),
      ),
    );
  }
}

class _HomeDesktopLayout extends StatelessWidget {
  const _HomeDesktopLayout();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Hackit MVP')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.10),
              scheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AdaptiveSpacing.maxContentWidth,
              ),
              child: Padding(
                padding: AdaptiveSpacing.screenPadding,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Posez votre question',
                                style: TextStyle(
                                  fontSize: SizeConfig.adaptiveFontSize(24),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: AdaptiveSpacing.large),
                              SizedBox(
                                width: SizeConfig.screenWidth * 0.6,
                                child: ChatInput(
                                  onSearch: (query) => provider.search(query),
                                  disabled: provider.loading,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (provider.loading)
                      const Expanded(
                          child: Center(child: CircularProgressIndicator())),
                    if (provider.error != null)
                      Padding(
                        padding: EdgeInsets.all(AdaptiveSpacing.medium),
                        child: Text(
                          '❌ ${provider.error}',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: SizeConfig.adaptiveFontSize(16),
                          ),
                        ),
                      ),
                    if (provider.result != null && !provider.loading)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: SummaryView(
                                title: provider.result!.title,
                                steps: provider.result!.steps,
                              ),
                            ),
                            SizedBox(width: AdaptiveSpacing.large),
                            Expanded(
                              flex: 1,
                              child: Column(
                                children: [
                                  VideoCard(
                                    title: provider.result!.title,
                                    videoUrl: provider.result!.videoUrl,
                                  ),
                                  // Placeholder for future desktop-only widgets
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
        ),
      ),
    );
  }
}
