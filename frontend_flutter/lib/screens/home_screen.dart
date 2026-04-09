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
      actions: [
        if (hasMessages)
          Tooltip(
            message: 'Nouveau brief',
            child: IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: () => provider.clearMessages(),
            ),
          ),
      ],
      child: Column(
        children: [
          Expanded(child: _ChatMessagesList()),
          ChatInput(
            onSearch: (query) {
              Provider.of<SearchProvider>(context, listen: false)
                  .searchStreaming(query);
            },
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
  // (modeId, modeLabel, exampleText, outputHint)
  static const _examples = [
    (
      'cadrer',
      '⚡ Cadrer',
      'Cadrer le lancement d\'une app mobile B2B pour 200 utilisateurs',
      'Note de cadrage complète + MECE',
    ),
    (
      'produire',
      '🔨 Produire',
      'Livrer un plan de migration vers le cloud en 4 semaines',
      'Plan MoSCoW + chemin critique',
    ),
    (
      'communiquer',
      '📣 Email',
      'Relancer un client sur un projet en retard de 3 semaines',
      'Email prêt à envoyer — Pyramid Principle',
    ),
    (
      'audit',
      '🔍 Audit 7j',
      'Diagnostiquer pourquoi le taux de conversion est tombé à 1,2 %',
      'Verdict P0/P1/P2 + causes racines',
    ),
    (
      'cadrer',
      '⚡ Cadrer',
      'Structurer une présentation de roadmap Q2 pour les investisseurs',
      'Answer First + recommandation ferme',
    ),
    (
      'produire',
      '🔨 Produire',
      'Rédiger les specs techniques d\'une API de paiement Stripe',
      'Definition of Done + risques',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 20 : 48,
          vertical: 32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Hero icon with gradient
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withValues(alpha: 0.18),
                      scheme.primaryContainer.withValues(alpha: 0.35),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.bolt_rounded, size: 40, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Du brief au livrable en 30 secondes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isMobile ? 22 : 26,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Décris ton défi ou ton livrable. Hackit génère un document consultant immédiatement actionnable.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 32),
              // Mode pills
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _modePill('⚡ Cadrer', scheme),
                  const SizedBox(width: 6),
                  _modePill('🔨 Produire', scheme),
                  const SizedBox(width: 6),
                  _modePill('📣 Email', scheme),
                  const SizedBox(width: 6),
                  _modePill('🔍 Audit', scheme),
                ],
              ),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'EXEMPLES — CLIQUEZ POUR LANCER',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: scheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Grid layout on wider screens
              LayoutBuilder(builder: (ctx, constraints) {
                final wide = constraints.maxWidth > 480;
                final cards = _examples
                    .map((e) => _ExampleCard(example: e))
                    .toList();
                if (wide) {
                  return Column(
                    children: [
                      for (var i = 0; i < cards.length; i += 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(child: cards[i]),
                              const SizedBox(width: 8),
                              if (i + 1 < cards.length)
                                Expanded(child: cards[i + 1])
                              else
                                const Expanded(child: SizedBox()),
                            ],
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  children: cards
                      .map((c) =>
                          Padding(padding: const EdgeInsets.only(bottom: 8), child: c))
                      .toList(),
                );
              }),
              const SizedBox(height: 8),
              Text(
                'Résultats basés sur Gemini 2.0 + sources web en temps réel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.30),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modePill(String label, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  /// (modeId, modeLabel, exampleText, outputHint)
  final (String, String, String, String) example;
  const _ExampleCard({required this.example});

  @override
  Widget build(BuildContext context) {
    final (modeId, modeLabel, text, hint) = example;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Provider.of<SearchProvider>(context, listen: false)
            .searchStreaming(text, context: {'mode': modeId}),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      modeLabel,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.north_east_rounded,
                      size: 14,
                      color: scheme.primary.withValues(alpha: 0.45)),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                text,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: scheme.onSurface.withValues(alpha: 0.88)),
              ),
              const SizedBox(height: 5),
              Text(
                '→ $hint',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: scheme.onSurface.withValues(alpha: 0.45)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
