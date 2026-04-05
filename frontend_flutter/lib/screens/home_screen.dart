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
    return AppScaffold(
      title: 'Hackit',
      subtitle: MediaQuery.of(context).size.width >= 600
          ? 'Du brief client au livrable actionnable'
          : null,
      leadingIcon: Icons.bolt_rounded,
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.red.shade400, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (m.content['message'] ?? 'Erreur') as String,
                  style: TextStyle(
                      color: Colors.red.shade600, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final lastQ = provider.lastQuery;
                  return TextButton.icon(
                    onPressed:
                        (provider.loading || lastQ == null || lastQ.isEmpty)
                            ? null
                            : () => provider.search(lastQ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Réessayer'),
                  );
                },
              )
            ],
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
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    const examples = [
      'Cadrer un projet CRM pour une PME de 50 personnes',
      'Préparer une démo produit pour un grand compte bancaire',
      'Auditer l\'existant et proposer un plan de refonte en 7 jours',
    ];

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
                child:
                    Icon(Icons.bolt_rounded, size: 38, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Prêt à construire ton plan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Décris le brief client ou le livrable à produire.\nHackit génère un plan structuré en quelques secondes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: scheme.onSurface.withValues(alpha: 0.60),
                ),
              ),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Exemples',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ...examples.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          final provider = context.read<SearchProvider>();
                          provider.setDraft(e);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(e,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.80))),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.north_west_rounded,
                                  size: 16,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.35)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
