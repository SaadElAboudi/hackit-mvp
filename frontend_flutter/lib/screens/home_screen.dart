import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../providers/search_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/health_badge.dart';
import '../widgets/summary_view.dart';
import '../widgets/lesson_view.dart';
import '../widgets/video_card.dart';
import '../widgets/chat_bubbles.dart';
import '../models/chat_message.dart';
import '../widgets/citations_view.dart';
import '../widgets/chapters_view.dart';
import '../models/base_search_result.dart';
import '../theme/app_extensions.dart';

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
        title: const Text(
          'Hackit',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: HealthBadge()),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AdaptiveSpacing.large,
              ),
              child: _ChatMessagesList(),
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
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: ChatInput(
                onSearch: (query) => provider.searchStreaming(query),
                disabled: provider.loading,
                onRegenerate: provider.regenerateLast,
                onEditLast: () {},
                getLastQuery: () => provider.lastQuery ?? '',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessagesList extends StatefulWidget {
  @override
  State<_ChatMessagesList> createState() => _ChatMessagesListState();
}

class _ChatMessagesListState extends State<_ChatMessagesList> {
  final _controller = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
    // Filtrage des messages vides pour éviter les bulles grises
    final messages = provider.messages.where((m) {
      if (m.role.name == 'user') {
        final text = (m.content['text'] ?? '') as String;
        return text.trim().isNotEmpty;
      }
      if (m.kind == ChatKind.text) {
        final text = (m.content['text'] ?? '') as String;
        return text.trim().isNotEmpty;
      }
      if (m.kind == ChatKind.steps) {
        final steps = m.content['steps'];
        return steps is List && steps.isNotEmpty;
      }
      if (m.kind == ChatKind.video) {
        final url = (m.content['videoUrl'] ?? '') as String;
        return url.trim().isNotEmpty;
      }
      if (m.kind == ChatKind.citations) {
        final c = m.content['citations'];
        return c is List && c.isNotEmpty;
      }
      if (m.kind == ChatKind.chapters) {
        final c = m.content['chapters'];
        return c is List && c.isNotEmpty;
      }
      if (m.kind == ChatKind.error) {
        final msg = (m.content['message'] ?? '') as String;
        return msg.trim().isNotEmpty;
      }
      return true;
    }).toList();
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Auto-scroll when messages appended
    if (messages.length > _lastCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      _lastCount = messages.length;
    }

    final children = <Widget>[];
    // Affiche toutes les bulles utilisateur, mais seulement la dernière bulle assistant
    ChatMessage? lastAssistant;
    for (final m in messages) {
      if (m.role == ChatRole.assistant) {
        lastAssistant = m;
      }
    }
    for (final m in messages) {
      if (m.role == ChatRole.user) {
        final text = (m.content['text'] ?? '') as String;
        if (text.isNotEmpty) {
          children.add(
            UserBubble(
              text: text,
              onEdit: provider.loading ? null : () => provider.setDraft(text),
              onRegenerate:
                  provider.loading ? null : () => provider.regenerateFor(text),
              disabled: provider.loading,
            ),
          );
          children.add(SizedBox(height: AdaptiveSpacing.small));
        }
      }
    }
    if (lastAssistant != null) {
      // Affiche la dernière bulle assistant selon son type
      final m = lastAssistant;
      if (m.kind == ChatKind.steps &&
          (m.content['videoUrl'] ?? '').toString().isNotEmpty) {
        final steps = List<String>.from(m.content['steps'] ?? const <String>[]);
        final title = (m.content['title'] ?? '') as String;
        final videoUrl = (m.content['videoUrl'] ?? '') as String;
        children.add(
          AssistantContainer(
            child: LessonView(
              title: title,
              steps: steps,
              videoUrl: videoUrl,
            ),
          ),
        );
      } else {
        switch (m.kind) {
          case ChatKind.steps:
            children.add(
              AssistantContainer(
                child: SummaryView(
                  title: (m.content['title'] ?? '') as String,
                  steps:
                      List<String>.from(m.content['steps'] ?? const <String>[]),
                ),
              ),
            );
            break;
          case ChatKind.text:
            children.add(
              AssistantContainer(
                child: Padding(
                  padding: EdgeInsets.all(AdaptiveSpacing.small),
                  child: Text((m.content['text'] ?? '') as String),
                ),
              ),
            );
            break;
          case ChatKind.error:
            children.add(
              AssistantContainer(
                child: Padding(
                  padding: EdgeInsets.all(AdaptiveSpacing.small),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (m.content['message'] ?? 'Erreur') as String,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      SizedBox(width: AdaptiveSpacing.small),
                      Builder(
                        builder: (context) {
                          final lastQ = provider.lastQuery;
                          return TextButton.icon(
                            onPressed: (provider.loading ||
                                    lastQ == null ||
                                    lastQ.isEmpty)
                                ? null
                                : () => provider.search(lastQ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Réessayer'),
                          );
                        },
                      )
                    ],
                  ),
                ),
              ),
            );
            break;
          default:
            break;
        }
      }
      children.add(SizedBox(height: AdaptiveSpacing.small));
    }

    if (provider.loading) {
      children.add(const LoadingBubbles());
      children.add(SizedBox(height: AdaptiveSpacing.small));
    }

    children.add(SizedBox(height: AdaptiveSpacing.large * 2));

    return ListView(
      controller: _controller,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? AdaptiveSpacing.medium : AdaptiveSpacing.large,
        vertical: AdaptiveSpacing.medium,
      ),
      children: children,
    );
  }
}

class _SourceChip extends StatelessWidget {
  final String source;
  const _SourceChip({required this.source});

  Color _color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>();
    final s = source.toLowerCase();
    if (s.contains('youtube')) return palette?.accentSuccess ?? scheme.primary;
    if (s.contains('yt-search')) return palette?.accentInfo ?? scheme.secondary;
    return palette?.accentWarning ?? scheme.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(context);
    return Padding(
      padding: EdgeInsets.only(
          left: AdaptiveSpacing.small, bottom: AdaptiveSpacing.small / 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.35), width: 1),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AdaptiveSpacing.small,
              vertical: AdaptiveSpacing.tiny + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, size: 14),
                const SizedBox(width: 4),
                Text(
                  source,
                  style: TextStyle(
                    fontSize: SizeConfig.adaptiveFontSize(11),
                    letterSpacing: 0.3,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.82),
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
        actions: const [
          Padding(padding: EdgeInsets.only(right: 16), child: HealthBadge()),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Expanded(child: _ChatMessagesList()),
              ChatInput(
                onSearch: (query) => provider.searchStreaming(query),
                disabled: provider.loading,
                onRegenerate: provider.regenerateLast,
                onEditLast: () {},
                getLastQuery: () => provider.lastQuery ?? '',
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
        actions: const [
          Padding(padding: EdgeInsets.only(right: 20), child: HealthBadge()),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            children: [
              Expanded(child: _ChatMessagesList()),
              ChatInput(
                onSearch: (query) => provider.searchStreaming(query),
                disabled: provider.loading,
                onRegenerate: provider.regenerateLast,
                onEditLast: () {},
                getLastQuery: () => provider.lastQuery ?? '',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
