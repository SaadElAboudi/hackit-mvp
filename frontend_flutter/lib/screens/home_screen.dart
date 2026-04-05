// ...existing code...
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../providers/search_provider.dart';
import '../widgets/lesson_view.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_bubbles.dart';
import '../models/chat_message.dart';
import '../widgets/citations_view.dart';
import '../widgets/chapters_view.dart';
import '../models/base_search_result.dart';
import '../widgets/app_scaffold.dart';
// ...existing code...

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SearchProvider>(context);
    final hasMessages = provider.messages.isNotEmpty;
    return AppScaffold(
      title: 'Hackit',
      subtitle: MediaQuery.of(context).size.width >= 600
          ? 'Du brief client au livrable actionnable'
          : null,
      leadingIcon: Icons.bolt_rounded,
      actions: hasMessages
          ? [
              Tooltip(
                message: 'Nouveau brief',
                child: IconButton(
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () => provider.clearMessages(),
                ),
              ),
            ]
          : null,
      child: Column(
        children: [
          Expanded(child: _ChatMessagesList()),
          ChatInput(
            onSearch: (query) =>
                Provider.of<SearchProvider>(context, listen: false)
                    .searchStreaming(query),
            onSearchWithContext: (query, contextData) =>
                Provider.of<SearchProvider>(context, listen: false)
                    .searchStreaming(query, context: contextData),
            disabled: Provider.of<SearchProvider>(context).loading,
            onRegenerate: Provider.of<SearchProvider>(context, listen: false)
                .regenerateLast,
            onEditLast: () {
              final provider =
                  Provider.of<SearchProvider>(context, listen: false);
              final last = provider.lastQuery;
              if (last != null && last.trim().isNotEmpty) {
                provider.setDraft(last);
              }
            },
            getLastQuery: () =>
                Provider.of<SearchProvider>(context, listen: false).lastQuery ??
                '',
            showTemplates: true,
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
  late final ScrollController _controller;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  void _scrollToBottom() {
    if (_controller.hasClients) {
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget buildAssistantWidget(ChatMessage m, SearchProvider provider) {
    switch (m.kind) {
      case ChatKind.steps:
        final steps = List<String>.from(m.content['steps'] ?? const <String>[]);
        final title = (m.content['title'] ?? '') as String;
        final videoUrl = (m.content['videoUrl'] ?? '') as String;
        final source = (m.content['source'] ?? '') as String;
        final deliveryMode = m.content['deliveryMode']?.toString();
        final rawDeliveryPlan = m.content['deliveryPlan'];
        final deliveryPlan = rawDeliveryPlan is Map
            ? Map<String, dynamic>.from(rawDeliveryPlan)
            : null;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LessonView(
            title: title,
            steps: steps,
            videoUrl: videoUrl,
            source: source,
            deliveryMode: deliveryMode,
            deliveryPlan: deliveryPlan,
          ),
        );
      case ChatKind.text:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AssistantContainer(
            child: Text(
              (m.content['text'] ?? '') as String,
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
          ),
        );
      case ChatKind.citations:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: CitationsView(
            citations: ((m.content['citations'] as List?) ?? [])
                .map((c) {
                  if (c is Citation) return c;
                  if (c is Map<String, dynamic>) return Citation.fromMap(c);
                  return null;
                })
                .whereType<Citation>()
                .toList(),
          ),
        );
      case ChatKind.chapters:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ChaptersView(
            chapters:
                chaptersFromAny(m.content['chapters'] ?? const <dynamic>[]),
            videoUrl: (m.content['videoUrl'] ?? '') as String,
          ),
        );
      case ChatKind.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AssistantContainer(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.red.shade400, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (m.content['message'] ??
                            'Une erreur s\'est produite, réessaie.')
                        as String,
                    style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final lastQ = provider.lastQuery;
                    return FilledButton.tonal(
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6)),
                      onPressed:
                          (provider.loading || lastQ == null || lastQ.isEmpty)
                              ? null
                              : () => provider.search(lastQ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, size: 14),
                          SizedBox(width: 4),
                          Text('Réessayer',
                              style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  },
                )
              ],
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SearchProvider>();
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

    if (messages.length > _lastCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      _lastCount = messages.length;
    }

    final children = <Widget>[];
    for (final m in messages) {
      if (m.role == ChatRole.user) {
        final text = (m.content['text'] ?? '') as String;
        if (text.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: UserBubble(
                text: text,
                onEdit: provider.loading ? null : () => provider.setDraft(text),
                onRegenerate: provider.loading
                    ? null
                    : () => provider.regenerateFor(text),
                disabled: provider.loading,
                textColor: Colors.white,
              ),
            ),
          );
        }
      } else if (m.role == ChatRole.assistant) {
        children.add(buildAssistantWidget(m, provider));
      }
    }
    if (provider.loading) {
      children.add(const LoadingBubbles());
      children.add(SizedBox(height: AdaptiveSpacing.small));
    }

    children.add(SizedBox(height: AdaptiveSpacing.large * 2));

    if (children.length == 1 && !provider.loading) {
      // Only the trailing spacer — show empty state
      return _EmptyState();
    }

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

class _EmptyState extends StatelessWidget {
  static const _examples = [
    ('⚡ Cadrer', 'Cadrer un CRM pour une PME de 50 personnes'),
    ('🔨 Produire', 'Rédiger les specs techniques d\'une API de paiement'),
    ('📣 Pitcher', 'Préparer le pitch deck d\'une levée Série A'),
    ('🔍 Audit 7j', 'Auditer et reprioriser le backlog produit en 7 jours'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 24 : 48,
          vertical: 32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.bolt_rounded, size: 38, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Du brief au plan en quelques secondes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Décris ton défi ou ton livrable. Hackit structure un plan d\'action immédiatement actionnable.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: scheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'LANCER UN EXEMPLE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: scheme.onSurface.withValues(alpha: 0.40),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ..._examples.map((e) {
                final (modeLabel, text) = e;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () =>
                          Provider.of<SearchProvider>(context, listen: false)
                              .searchStreaming(text),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer
                                    .withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                modeLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimaryContainer),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.82)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.play_arrow_rounded,
                                size: 18,
                                color: scheme.primary.withValues(alpha: 0.55)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
