import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/room.dart';
import '../providers/room_provider.dart';
import '../services/project_service.dart' show ProjectService;

/// The main chat screen for a salon.
///
/// Features:
/// - Real-time messages via WebSocket (auto-reconnect)
/// - AI colleague participates when mentioned with @ia
/// - Document messages appear as a special card (challengeable)
/// - Any member can add challenges/directives for the AI
/// - AI thinking indicator + reconnecting banner
class SalonChatScreen extends StatefulWidget {
  final Room room;
  const SalonChatScreen({super.key, required this.room});

  @override
  State<SalonChatScreen> createState() => _SalonChatScreenState();
}

class _SalonChatScreenState extends State<SalonChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _directivesOpen = false;
  late final TextEditingController _directivesCtrl;

  String get _myUserId => ProjectService.currentUserId ?? '';
  String get _displayName {
    final uid = _myUserId;
    return 'User_${uid.isEmpty ? '????' : uid.substring(uid.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    _directivesCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = context.read<RoomProvider>();
      await prov.openRoom(widget.room);
      _directivesCtrl.text = prov.currentRoom?.aiDirectives ?? '';
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _directivesCtrl.dispose();
    _scrollCtrl.dispose();
    context.read<RoomProvider>().closeRoom();
    super.dispose();
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (animated) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    _inputCtrl.clear();

    final prov = context.read<RoomProvider>();
    final ok = await prov.sendMessage(text, displayName: _displayName);

    if (ok) {
      _scrollToBottom(animated: true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(prov.sendError ?? 'Erreur lors de l\'envoi'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prov = context.watch<RoomProvider>();
    final room = prov.currentRoom ?? widget.room;

    // Scroll to bottom whenever new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (prov.messages.isNotEmpty && !prov.loadingMessages) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _buildAppBar(context, room, scheme),
      body: Column(
        children: [
          // Reconnecting banner
          if (prov.wsReconnecting)
            Container(
              color: Colors.orange.shade800,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Reconnexion en cours…',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),

          // AI Directives panel (collapsible)
          _DirectivesPanel(
            open: _directivesOpen,
            controller: _directivesCtrl,
            currentDirectives: room.aiDirectives,
            onToggle: () => setState(() => _directivesOpen = !_directivesOpen),
            onSave: (d) async {
              final ok = await prov.updateDirectives(d);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Directives enregistrées ✓'
                        : 'Erreur lors de la sauvegarde'),
                  ),
                );
              }
            },
          ),

          // Message list
          Expanded(
            child: prov.loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : prov.messages.isEmpty && !prov.aiThinking
                    ? _EmptyChat(roomName: room.name)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        itemCount:
                            prov.messages.length + (prov.aiThinking ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == prov.messages.length) {
                            return _AITypingBubble(scheme: scheme);
                          }
                          final msg = prov.messages[i];
                          final isMe = msg.senderId == _myUserId;
                          return _MessageBubble(
                            message: msg,
                            isMe: isMe,
                            onChallenge: msg.isDocument
                                ? (content) => prov.addChallenge(
                                      msg.id,
                                      content,
                                      displayName: _displayName,
                                    )
                                : null,
                          );
                        },
                      ),
          ),

          // Input bar
          _InputBar(
            controller: _inputCtrl,
            sending: prov.sendingMessage,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, Room room, ColorScheme scheme) {
    return AppBar(
      backgroundColor: scheme.surface,
      elevation: 0,
      titleSpacing: 0,
      leading: const BackButton(),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text(
              room.name.isNotEmpty ? room.name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${room.memberCount} membre${room.memberCount > 1 ? 's' : ''} + IA',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Directives toggle
        IconButton(
          icon: Icon(
            Icons.tune_rounded,
            color: _directivesOpen ? scheme.primary : null,
          ),
          tooltip: 'Directives pour l\'IA',
          onPressed: () => setState(() => _directivesOpen = !_directivesOpen),
        ),
      ],
    );
  }
}

// ── Directives panel ──────────────────────────────────────────────────────────

class _DirectivesPanel extends StatelessWidget {
  final bool open;
  final TextEditingController controller;
  final String currentDirectives;
  final VoidCallback onToggle;
  final Future<void> Function(String) onSave;

  const _DirectivesPanel({
    required this.open,
    required this.controller,
    required this.currentDirectives,
    required this.onToggle,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!open) return const SizedBox.shrink();

    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Directives pour l\'IA',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                'Guident le comportement de l\'IA dans ce salon',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  'Ex: Réponds toujours en français, sois concis, utilise des listes…',
              filled: true,
              fillColor: scheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => onSave(controller.text.trim()),
              child: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final RoomMessage message;
  final bool isMe;
  final Future<bool> Function(String)? onChallenge;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onChallenge,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDocument) {
      return _DocumentCard(message: message, onChallenge: onChallenge);
    }

    final scheme = Theme.of(context).colorScheme;
    final isAI = message.isAI;

    Color bubbleColor;
    Color textColor;
    if (isAI) {
      bubbleColor = scheme.secondaryContainer;
      textColor = scheme.onSecondaryContainer;
    } else if (isMe) {
      bubbleColor = scheme.primary;
      textColor = scheme.onPrimary;
    } else {
      bubbleColor = scheme.surfaceContainerHigh;
      textColor = scheme.onSurface;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _SenderAvatar(name: message.senderName, isAI: isAI, scheme: scheme),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 2),
                    child: Text(
                      isAI ? '✦ IA' : message.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isAI
                            ? scheme.secondary
                            : scheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPress: () => _copyText(context, message.content),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(18).copyWith(
                        bottomLeft: isMe
                            ? const Radius.circular(18)
                            : const Radius.circular(4),
                        bottomRight: isMe
                            ? const Radius.circular(4)
                            : const Radius.circular(18),
                      ),
                    ),
                    child: SelectableText(
                      message.content,
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _copyText(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copié dans le presse-papier'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

// ── Document card (challengeable deliverable) ─────────────────────────────────

class _DocumentCard extends StatefulWidget {
  final RoomMessage message;
  final Future<bool> Function(String)? onChallenge;

  const _DocumentCard({required this.message, this.onChallenge});

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msg = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.secondaryContainer, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(
                children: [
                  Icon(Icons.description_rounded,
                      size: 18, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.documentTitle ?? 'Livrable IA',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '✦ IA • ${msg.challenges.length} challenge${msg.challenges.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),

            // Content (collapsible)
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: SelectableText(
                  msg.content,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],

            // Challenges
            if (msg.challenges.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: Text(
                  'Challenges',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              ...msg.challenges.map(
                (c) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.reply_rounded,
                          size: 14, color: scheme.onSurface.withOpacity(0.4)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${c.userName}: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: scheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            TextSpan(
                              text: c.content,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Row(
                children: [
                  TextButton.icon(
                    icon:
                        const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text('Challenger',
                        style: TextStyle(fontSize: 13)),
                    onPressed: widget.onChallenge != null
                        ? () => _showChallengeDialog(context)
                        : null,
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copier', style: TextStyle(fontSize: 13)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: msg.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copié'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChallengeDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Challenger ce livrable'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Votre retour sera visible par tous et pourra guider l\'IA à réviser le document.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Ex: La section 2 manque de détails sur le budget…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (ok == true && widget.onChallenge != null) {
      await widget.onChallenge!(ctrl.text.trim());
    }
  }
}

// ── Sender avatar ─────────────────────────────────────────────────────────────

class _SenderAvatar extends StatelessWidget {
  final String name;
  final bool isAI;
  final ColorScheme scheme;

  const _SenderAvatar({
    required this.name,
    required this.isAI,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor:
          isAI ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      foregroundColor: isAI ? scheme.secondary : scheme.onSurface,
      child: Text(
        isAI ? '✦' : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
        style: TextStyle(
          fontSize: isAI ? 13 : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── AI typing bubble ──────────────────────────────────────────────────────────

class _AITypingBubble extends StatelessWidget {
  final ColorScheme scheme;
  const _AITypingBubble({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.secondaryContainer,
            child: Text(
              '✦',
              style: TextStyle(color: scheme.secondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '✦ IA réfléchit',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSecondaryContainer.withOpacity(0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message… (mentionnez @ia pour l\'IA)',
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onSubmitted: sending ? null : (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: sending
                ? SizedBox(
                    width: 44,
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: scheme.primary,
                      ),
                    ),
                  )
                : IconButton.filled(
                    icon: const Icon(Icons.send_rounded, size: 20),
                    onPressed: onSend,
                    tooltip: 'Envoyer',
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Empty chat state ──────────────────────────────────────────────────────────

class _EmptyChat extends StatelessWidget {
  final String roomName;
  const _EmptyChat({required this.roomName});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '✦',
              style: TextStyle(fontSize: 48, color: scheme.secondary),
            ),
            const SizedBox(height: 16),
            Text(
              'Bienvenue dans $roomName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Envoyez un message pour démarrer.\nMentionnez @ia pour impliquer votre collègue IA.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.55),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
