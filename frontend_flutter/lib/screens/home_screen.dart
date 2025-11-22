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
// ...existing code...
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: Colors.white,
          elevation: 3,
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble_rounded,
                  color: Color(0xFF00C48C), size: 28),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hackit',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Color(0xFF222B45),
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Color(0x22000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 38,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Color(0xFF00C48C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Déconnexion',
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('auth_token');
                await prefs.remove('userId');
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
            IconButton(icon: Icon(Icons.help_outline), onPressed: () {}),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _ChatMessagesList()),
          ChatInput(
            onSearch: (query) =>
                Provider.of<SearchProvider>(context, listen: false)
                    .searchStreaming(query),
            disabled: Provider.of<SearchProvider>(context).loading,
            onRegenerate: Provider.of<SearchProvider>(context, listen: false)
                .regenerateLast,
            onEditLast: () {},
            getLastQuery: () =>
                Provider.of<SearchProvider>(context, listen: false).lastQuery ??
                '',
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
        return Card(
          elevation: 5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: LessonView(
              title: title,
              steps: steps,
              videoUrl: videoUrl,
            ),
          ),
        );
      case ChatKind.text:
        return Card(
          elevation: 5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: AssistantContainer(
              child: Text(
                (m.content['text'] ?? '') as String,
                style: const TextStyle(
                    fontSize: 17,
                    color: Colors.black,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        );
      case ChatKind.citations:
        return Card(
          elevation: 5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
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
          ),
        );
      case ChatKind.chapters:
        return Card(
          elevation: 5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: ChaptersView(
              chapters:
                  chaptersFromAny(m.content['chapters'] ?? const <dynamic>[]),
              videoUrl: (m.content['videoUrl'] ?? '') as String,
            ),
          ),
        );
      case ChatKind.error:
        return Card(
          elevation: 5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    (m.content['message'] ?? 'Erreur') as String,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 12),
                Builder(
                  builder: (context) {
                    final lastQ = provider.lastQuery;
                    return TextButton.icon(
                      onPressed:
                          (provider.loading || lastQ == null || lastQ.isEmpty)
                              ? null
                              : () => provider.search(lastQ),
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.blueAccent),
                      label: const Text('Réessayer'),
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
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: UserBubble(
                  text: text,
                  onEdit:
                      provider.loading ? null : () => provider.setDraft(text),
                  onRegenerate: provider.loading
                      ? null
                      : () => provider.regenerateFor(text),
                  disabled: provider.loading,
                  textColor: Colors.black,
                ),
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
