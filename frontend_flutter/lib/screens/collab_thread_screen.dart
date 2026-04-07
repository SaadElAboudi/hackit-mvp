import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/collab.dart';
import '../providers/collab_provider.dart';
import '../services/project_service.dart';
import '../core/responsive/size_config.dart';

/// Full-screen collaborative chat view for a single Thread.
/// Connects via WebSocket for real-time presence + message broadcast.
class CollabThreadScreen extends StatefulWidget {
  final CollabProject project;
  final CollabThread thread;

  const CollabThreadScreen({
    super.key,
    required this.project,
    required this.thread,
  });

  @override
  State<CollabThreadScreen> createState() => _CollabThreadScreenState();
}

class _CollabThreadScreenState extends State<CollabThreadScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription<WsEvent>? _wsSub;
  bool _pinNext = false;

  @override
  void initState() {
    super.initState();
    _connectWs();
    // Load full thread (with messages)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<CollabProvider>()
          .openThread(widget.project.slug, widget.thread.id);
    });
  }

  void _connectWs() {
    // Reuse the userId for presence tracking (reads from SharedPreferences cache)
    final userId = ProjectService.currentUserId ?? 'anon';
    final stream = projectService.subscribeToThread(widget.thread.id, userId);
    _wsSub = stream.listen(_onWsEvent);
  }

  void _onWsEvent(WsEvent event) {
    if (!mounted) return;
    final prov = context.read<CollabProvider>();
    switch (event.type) {
      case WsEventType.joined:
        // Successful (re)connection — clear reconnecting state
        prov.onWsConnected();
      case WsEventType.message:
        final msgJson = event.payload['message'];
        if (msgJson is Map<String, dynamic>) {
          prov.onWsNewMessage(ThreadMessage.fromJson(msgJson));
          _scrollToBottom();
        }
      case WsEventType.typing:
        final uid = event.payload['userId'] as String?;
        prov.onWsTyping(uid);
        _scrollToBottom();
      case WsEventType.reconnecting:
        prov.onWsReconnecting();
      case WsEventType.presence:
        final ids = (event.payload['userIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        prov.onWsPresence(ids);
      default:
        break;
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    projectService.unsubscribeFromThread(widget.thread.id);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    final prov = context.read<CollabProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await prov.sendMessage(
      widget.project.slug,
      widget.thread.id,
      prompt: text,
      pin: _pinNext,
    );
    if (!mounted) return;
    setState(() => _pinNext = false);
    if (ok) {
      _scrollToBottom();
    } else {
      final errMsg = prov.threadError ?? 'Erreur inconnue';
      messenger.showSnackBar(
        SnackBar(
          content: Text(errMsg),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _buildAppBar(scheme),
      body: Column(
        children: [
          // Reconnection banner
          Consumer<CollabProvider>(
            builder: (_, prov, __) => prov.wsReconnecting
                ? Container(
                    color: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Reconnexion en cours…',
                          style: TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(child: _buildMessageList(scheme)),
          _buildInputBar(scheme),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme scheme) {
    return AppBar(
      backgroundColor: scheme.surface,
      elevation: 0,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.thread.title,
            style: TextStyle(
              fontSize: SizeConfig.adaptiveFontSize(15),
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          Consumer<CollabProvider>(
            builder: (_, prov, __) {
              final count = prov.presenceUserIds.length;
              if (count == 0) return const SizedBox.shrink();
              return Text(
                '$count en ligne',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.history_rounded),
          tooltip: 'Versions',
          onPressed: () => _showVersionsPanel(context),
        ),
      ],
    );
  }

  Widget _buildMessageList(ColorScheme scheme) {
    return Consumer<CollabProvider>(
      builder: (context, prov, _) {
        final msgs = prov.activeThread?.messages ?? widget.thread.messages;

        if (msgs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 48, color: scheme.onSurface.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text(
                    'Démarrez la conversation',
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: msgs.length + (prov.sendingMessage || prov.remoteTyping ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i == msgs.length) {
              return _TypingIndicator(scheme: scheme);
            }
            return _MessageBubble(
              message: msgs[i],
              scheme: scheme,
              project: widget.project,
              thread: widget.thread,
            );
          },
        );
      },
    );
  }

  Widget _buildInputBar(ColorScheme scheme) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
              top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.3))),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pinNext)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.push_pin_rounded,
                        size: 13, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'La prochaine réponse sera épinglée en version',
                      style: TextStyle(fontSize: 11.5, color: scheme.primary),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.push_pin_outlined,
                    color: _pinNext
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.4),
                    size: 20,
                  ),
                  tooltip: 'Épingler en version',
                  onPressed: () => setState(() => _pinNext = !_pinNext),
                ),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Envoyer à Gemini…',
                      hintStyle: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.35)),
                      filled: true,
                      fillColor: scheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<CollabProvider>(
                  builder: (_, prov, __) => IconButton.filled(
                    onPressed: prov.sendingMessage ? null : _send,
                    icon: prov.sendingMessage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showVersionsPanel(BuildContext context) {
    final prov = context.read<CollabProvider>();
    prov.loadVersions(widget.project.slug, widget.thread.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: prov,
        child: _VersionsPanel(
          project: widget.project,
          thread: widget.thread,
        ),
      ),
    );
  }
}

// ─── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ThreadMessage message;
  final ColorScheme scheme;
  final CollabProject project;
  final CollabThread thread;

  const _MessageBubble({
    required this.message,
    required this.scheme,
    required this.project,
    required this.thread,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _buildUserBubble(context);
    if (message.role == 'system') return const SizedBox.shrink();
    return _buildAiBubble(context);
  }

  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            fontSize: SizeConfig.adaptiveFontSize(13.5),
            color: scheme.onPrimary,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _buildAiBubble(BuildContext context) {
    final isPinned = message.versionRef != null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(bottom: 4, right: 6),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    size: 12, color: scheme.onSecondaryContainer),
              ),
              Text(
                'Gemini',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              if (isPinned) ...[
                const SizedBox(width: 6),
                Icon(Icons.push_pin_rounded, size: 11, color: scheme.primary),
                Text(
                  ' version épinglée',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.primary,
                  ),
                ),
              ],
            ]),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: _ReadyToSendCardContent(content: message.content),
            ),
            _MessageActions(
                message: message,
                project: project,
                thread: thread,
                scheme: scheme),
          ],
        ),
      ),
    );
  }
}

/// Simple rich-text renderer for Gemini AI messages inside a thread bubble.
class _ReadyToSendCardContent extends StatelessWidget {
  final String content;
  const _ReadyToSendCardContent({required this.content});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = content.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) => _renderLine(line, scheme)).toList(),
    );
  }

  Widget _renderLine(String line, ColorScheme scheme) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return const SizedBox(height: 4);

    final baseStyle = TextStyle(
      fontSize: SizeConfig.adaptiveFontSize(13.5),
      height: 1.5,
      color: scheme.onSurface.withValues(alpha: 0.87),
    );

    // Bullet point
    if (trimmed.startsWith('• ') ||
        trimmed.startsWith('- ') ||
        trimmed.startsWith('* ')) {
      final text = trimmed.substring(2);
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: baseStyle.copyWith(color: scheme.primary)),
            Expanded(child: _richText(text, baseStyle, scheme)),
          ],
        ),
      );
    }

    // Bold header (## or **text**)
    if (trimmed.startsWith('## ') || trimmed.startsWith('### ')) {
      final text = trimmed.replaceAll(RegExp(r'^#{1,3}\s+'), '');
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          text,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: _richText(trimmed, baseStyle, scheme),
    );
  }

  /// Renders inline bold (**text**) as bold spans.
  Widget _richText(String text, TextStyle base, ColorScheme scheme) {
    final spans = <InlineSpan>[];
    final boldRegex = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in boldRegex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style:
            base.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _MessageActions extends StatelessWidget {
  final ThreadMessage message;
  final CollabProject project;
  final CollabThread thread;
  final ColorScheme scheme;

  const _MessageActions({
    required this.message,
    required this.project,
    required this.thread,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    if (!message.isAi) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        children: [
          _ActionBtn(
            icon: Icons.thumb_up_outlined,
            label: 'Pertinent',
            color: Colors.green.shade700,
            onTap: () => _sendFeedback(context, 'positive'),
          ),
          const SizedBox(width: 4),
          _ActionBtn(
            icon: Icons.thumb_down_outlined,
            label: 'À revoir',
            color: Colors.orange.shade700,
            onTap: () => _sendFeedback(context, 'negative'),
          ),
          const SizedBox(width: 4),
          _ActionBtn(
            icon: Icons.copy_outlined,
            label: 'Copier',
            color: scheme.onSurface.withValues(alpha: 0.5),
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Copié'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _sendFeedback(BuildContext ctx, String decision) {
    // Fire-and-forget feedback
    projectService
        .approveVersion(
          project.slug,
          thread.id,
          message.versionRef ?? message.id,
          decision: decision == 'positive' ? 'approved' : 'rejected',
        )
        .ignore();
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(decision == 'positive'
            ? '👍 Feedback envoyé'
            : '👎 Feedback envoyé'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─── Typing indicator ─────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final ColorScheme scheme;
  const _TypingIndicator({required this.scheme});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final v = ((_ctrl.value * 3 - i) % 1.0).clamp(0.0, 1.0);
                final opacity = (v < 0.5 ? v * 2 : (1 - v) * 2).clamp(0.3, 1.0);
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: widget.scheme.primary.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

// ─── Versions panel ────────────────────────────────────────────────────────────

class _VersionsPanel extends StatelessWidget {
  final CollabProject project;
  final CollabThread thread;
  const _VersionsPanel({required this.project, required this.thread});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Versions',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Consumer<CollabProvider>(
                builder: (ctx, prov, _) {
                  if (prov.versionsState == CollabLoadState.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (prov.versions.isEmpty) {
                    return Center(
                      child: Text(
                        'Aucune version épinglée',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: prov.versions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final v = prov.versions[i];
                      return _VersionCard(
                        version: v,
                        project: project,
                        thread: thread,
                        scheme: scheme,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final CollabVersion version;
  final CollabProject project;
  final CollabThread thread;
  final ColorScheme scheme;

  const _VersionCard({
    required this.version,
    required this.project,
    required this.thread,
    required this.scheme,
  });

  Color get _statusColor {
    return switch (version.status) {
      'approved' => Colors.green.shade700,
      'rejected' => Colors.red.shade700,
      'merged' => scheme.primary,
      _ => scheme.onSurface.withValues(alpha: 0.45),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'v${version.number}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (version.label != null)
                Expanded(
                  child: Text(
                    version.label!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  version.status,
                  style: TextStyle(
                    fontSize: 11,
                    color: _statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            version.prompt,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _VoteBtn(
                icon: Icons.thumb_up_outlined,
                count: version.approvedCount,
                color: Colors.green.shade700,
                onTap: () => context.read<CollabProvider>().voteVersion(
                    project.slug, thread.id, version.id, 'approved'),
              ),
              const SizedBox(width: 8),
              _VoteBtn(
                icon: Icons.thumb_down_outlined,
                count: version.rejectedCount,
                color: Colors.red.shade700,
                onTap: () => context.read<CollabProvider>().voteVersion(
                    project.slug, thread.id, version.id, 'rejected'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoteBtn extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final VoidCallback onTap;
  const _VoteBtn(
      {required this.icon,
      required this.count,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
