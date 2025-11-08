import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../providers/search_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/summary_view.dart';
import '../widgets/video_card.dart';
import '../widgets/chat_bubbles.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFF7F8FA);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: const Text('Hackit'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AdaptiveSpacing.medium,
              ),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  SizedBox(height: AdaptiveSpacing.small),
                  if (provider.lastQuery != null)
                    UserBubble(text: provider.lastQuery!),
                  if (provider.loading) const LoadingBubbles(),
                  if (provider.error != null)
                    Padding(
                      padding: EdgeInsets.only(
                        top: AdaptiveSpacing.small,
                        right: AdaptiveSpacing.small,
                        left: AdaptiveSpacing.small,
                      ),
                      child: Text(
                        '❌ ${provider.error}',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: SizeConfig.adaptiveFontSize(14),
                        ),
                      ),
                    ),
                  if (provider.result != null && !provider.loading) ...[
                    AssistantContainer(
                      child: SummaryView(
                        title: provider.result!.title,
                        steps: provider.result!.steps,
                      ),
                    ),
                    SizedBox(height: AdaptiveSpacing.small),
                    AssistantContainer(
                      child: VideoCard(
                        title: provider.result!.title,
                        videoUrl: provider.result!.videoUrl,
                      ),
                    ),
                  ],
                  SizedBox(height: AdaptiveSpacing.large * 2),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                )
              ],
            ),
            child: ChatInput(
              onSearch: (query) => provider.search(query),
              disabled: provider.loading,
            ),
          ),
        ],
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
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFF7F8FA);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: const Text('Hackit'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: AdaptiveSpacing.large,
                    vertical: AdaptiveSpacing.medium,
                  ),
                  children: [
                    if (provider.lastQuery != null)
                      UserBubble(text: provider.lastQuery!),
                    if (provider.loading) const LoadingBubbles(),
                    if (provider.error != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top: AdaptiveSpacing.small,
                        ),
                        child: Text(
                          '❌ ${provider.error}',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: SizeConfig.adaptiveFontSize(14),
                          ),
                        ),
                      ),
                    if (provider.result != null && !provider.loading) ...[
                      AssistantContainer(
                        child: SummaryView(
                          title: provider.result!.title,
                          steps: provider.result!.steps,
                        ),
                      ),
                      SizedBox(height: AdaptiveSpacing.small),
                      AssistantContainer(
                        child: VideoCard(
                          title: provider.result!.title,
                          videoUrl: provider.result!.videoUrl,
                        ),
                      ),
                    ],
                    SizedBox(height: AdaptiveSpacing.large * 2),
                  ],
                ),
              ),
              ChatInput(
                onSearch: (query) => provider.search(query),
                disabled: provider.loading,
              ),
            ],
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
    final bg = scheme.brightness == Brightness.dark
        ? const Color(0xFF111213)
        : const Color(0xFFF5F6F7);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Hackit'),
        backgroundColor: bg,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: AdaptiveSpacing.large,
                    vertical: AdaptiveSpacing.medium,
                  ),
                  children: [
                    if (provider.lastQuery != null)
                      UserBubble(text: provider.lastQuery!),
                    if (provider.loading) const LoadingBubbles(),
                    if (provider.error != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top: AdaptiveSpacing.small,
                        ),
                        child: Text(
                          '❌ ${provider.error}',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: SizeConfig.adaptiveFontSize(14),
                          ),
                        ),
                      ),
                    if (provider.result != null && !provider.loading) ...[
                      AssistantContainer(
                        child: SummaryView(
                          title: provider.result!.title,
                          steps: provider.result!.steps,
                        ),
                      ),
                      SizedBox(height: AdaptiveSpacing.small),
                      AssistantContainer(
                        child: VideoCard(
                          title: provider.result!.title,
                          videoUrl: provider.result!.videoUrl,
                        ),
                      ),
                    ],
                    SizedBox(height: AdaptiveSpacing.large * 2),
                  ],
                ),
              ),
              ChatInput(
                onSearch: (query) => provider.search(query),
                disabled: provider.loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
