import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/room.dart';
import '../providers/room_provider.dart';
import '../services/personal_ai_service.dart';
import '../services/project_service.dart' show ProjectService;
import '../utils/web_download.dart';
import 'profile_screen.dart';

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
  bool _aiPanelOpen = false;
  final _aiInputCtrl = TextEditingController();
  final List<AiMessage> _aiHistory = [];
  bool _aiThinking = false;
  String? _aiError;
  bool _isAtBottom = true; // track whether user is near the bottom
  String get _myUserId => ProjectService.currentUserId ?? '';
  String get _displayName {
    final uid = _myUserId;
    return ProjectService.currentDisplayName ??
        'User_${uid.isEmpty ? '????' : uid.substring(uid.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      _isAtBottom = pos.pixels >= pos.maxScrollExtent - 100;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = context.read<RoomProvider>();
      await prov.openRoom(widget.room);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _aiInputCtrl.dispose();
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
    final errorColor = Theme.of(context).colorScheme.error;
    _inputCtrl.clear();

    final prov = context.read<RoomProvider>();
    final ok = await prov.sendMessage(text, displayName: _displayName);

    if (ok) {
      _isAtBottom = true; // always scroll to own outgoing message
      _scrollToBottom(animated: true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(prov.sendError ?? 'Erreur lors de l\'envoi'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _share() async {
    final prov = context.read<RoomProvider>();
    final room = prov.currentRoom ?? widget.room;
    final link = await prov.getInviteLink();
    if (!mounted) return;
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de générer le lien')),
      );
      return;
    }
    await Share.share(
      'Rejoins le salon "${room.name}" sur HackIt :\n$link',
      subject: 'Invitation au salon ${room.name}',
    );
  }

  void _showMembersPanel() {
    final prov = context.read<RoomProvider>();
    final room = prov.currentRoom ?? widget.room;
    final onlineIds = prov.onlineUserIds;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MembersSheet(
        room: room,
        onlineUserIds: onlineIds,
        myUserId: _myUserId,
      ),
    );
  }

  void _showAttachDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AttachDocumentSheet(
        displayName: _displayName,
        onUpload: (title, content) async {
          final prov = context.read<RoomProvider>();
          final ok = await prov.uploadDocument(
            content,
            title: title,
            displayName: _displayName,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok
                    ? 'Document partagé ✓'
                    : 'Erreur lors du partage du document'),
              ),
            );
            if (ok) _scrollToBottom(animated: true);
          }
        },
      ),
    );
  }

  Future<void> _sendToAi() async {
    final text = _aiInputCtrl.text.trim();
    if (text.isEmpty) return;
    final key = ProjectService.geminiKey;
    if (key == null || key.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configure ta clé Gemini dans ton profil (icône 👤)'),
          ),
        );
      }
      return;
    }
    _aiInputCtrl.clear();
    final userMsg = AiMessage(role: 'user', text: text);
    setState(() {
      _aiHistory.add(userMsg);
      _aiThinking = true;
      _aiError = null;
    });
    try {
      final prov = context.read<RoomProvider>();
      final msgs = prov.messages;
      final recent = msgs.length > 15 ? msgs.sublist(msgs.length - 15) : msgs;
      final ctxLines =
          recent.map((m) => '${m.senderName}: ${m.content}').join('\n');
      final systemPrompt = 'Tu es un assistant IA personnel et confidentiel. '
          'Seul l\'utilisateur te voit.\n\n'
          'Contexte du salon (derniers messages) :\n$ctxLines\n\n'
          'Aide l\'utilisateur à réfléchir, rédiger ou analyser. '
          'Réponds de façon concise et en français.';
      final svc = PersonalAiService(apiKey: key);
      final reply = await svc.chat(_aiHistory, text, systemPrompt: systemPrompt);
      if (!mounted) return;
      setState(() {
        _aiHistory.add(AiMessage(role: 'model', text: reply));
        _aiThinking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiThinking = false;
        _aiError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prov = context.watch<RoomProvider>();
    final room = prov.currentRoom ?? widget.room;

    // Auto-scroll only when the user is already at the bottom
    // (prevents hijacking scroll when user reads old messages)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAtBottom && prov.messages.isNotEmpty && !prov.loadingMessages) {
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
                            onExport: msg.isDocument
                                ? (content, title) =>
                                    _exportDocument(content, title)
                                : null,
                          );
                        },
                      ),
          ),

          // Personal AI panel (private, collapsible)
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: _aiPanelOpen
                ? _AiPanel(
                    history: _aiHistory,
                    thinking: _aiThinking,
                    error: _aiError,
                    inputCtrl: _aiInputCtrl,
                    onSend: _sendToAi,
                    onClose: () => setState(() => _aiPanelOpen = false),
                    onUseInChat: (text) {
                      _aiInputCtrl.clear();
                      _inputCtrl.text = text;
                    },
                  )
                : const SizedBox.shrink(),
          ),

          // Input bar
          _InputBar(
            controller: _inputCtrl,
            sending: prov.sendingMessage,
            onSend: _send,
            onAttach: _showAttachDialog,
            onAiToggle: () => setState(() => _aiPanelOpen = !_aiPanelOpen),
            aiPanelOpen: _aiPanelOpen,
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, Room room, ColorScheme scheme) {
    final prov = context.watch<RoomProvider>();
    final onlineCount = prov.onlineUserIds.length;

    return AppBar(
      backgroundColor: scheme.surface,
      elevation: 0,
      titleSpacing: 0,
      leading: const BackButton(),
      title: GestureDetector(
        onTap: _showMembersPanel,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text(
                room.name.isNotEmpty ? room.name[0].toUpperCase() : '?',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                  Row(
                    children: [
                      Text(
                        '${room.memberCount} membre${room.memberCount > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      if (onlineCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22c55e),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$onlineCount en ligne',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Profile screen
        IconButton(
          icon: const Icon(Icons.person_outline_rounded),
          tooltip: 'Mon profil',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
        ),
        // Members panel
        IconButton(
          icon: const Icon(Icons.group_rounded),
          tooltip: 'Membres',
          onPressed: _showMembersPanel,
        ),
        // Share / Invite
        IconButton(
          icon: const Icon(Icons.ios_share_rounded),
          tooltip: 'Partager le salon',
          onPressed: _share,
        ),
      ],
    );
  }

  void _exportDocument(String content, String? title) {
    final fileName =
        '${(title ?? 'document').replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}.md';
    if (kIsWeb) {
      try {
        triggerMarkdownDownload(content, fileName);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Téléchargement de $fileName'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      } catch (_) {
        // Fall through to clipboard
      }
    }
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Document copié dans le presse-papier'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ── Personal AI panel ─────────────────────────────────────────────────────────

class _AiPanel extends StatefulWidget {
  final List<AiMessage> history;
  final bool thinking;
  final String? error;
  final TextEditingController inputCtrl;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final void Function(String text) onUseInChat;

  const _AiPanel({
    required this.history,
    required this.thinking,
    this.error,
    required this.inputCtrl,
    required this.onSend,
    required this.onClose,
    required this.onUseInChat,
  });

  @override
  State<_AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<_AiPanel> {
  final _listCtrl = ScrollController();

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_AiPanel old) {
    super.didUpdateWidget(old);
    if (widget.history.length != old.history.length ||
        widget.thinking != old.thinking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_listCtrl.hasClients) {
          _listCtrl.animateTo(
            _listCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty =
        widget.history.isEmpty && !widget.thinking && widget.error == null;
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: scheme.secondaryContainer, width: 1.5),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 4),
            child: Row(
              children: [
                Text('✦', style: TextStyle(color: scheme.secondary, fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  'Copilote IA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Privé · visible uniquement par toi',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.45),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Fermer',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Conversation
          Expanded(
            child: empty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Posez une question à votre IA.\nElle dispose du contexte du salon.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface.withOpacity(0.4),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _listCtrl,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: widget.history.length +
                        (widget.thinking ? 1 : 0) +
                        (widget.error != null ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i < widget.history.length) {
                        final msg = widget.history[i];
                        return _AiMessageRow(
                          msg: msg,
                          scheme: scheme,
                          onUseInChat: msg.role == 'model'
                              ? () => widget.onUseInChat(msg.text)
                              : null,
                        );
                      }
                      if (widget.thinking && i == widget.history.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Text('✦',
                                  style: TextStyle(
                                      color: scheme.secondary, fontSize: 13)),
                              const SizedBox(width: 8),
                              Text(
                                'Réfléchit…',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurface.withOpacity(0.5),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: scheme.secondary),
                              ),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.error ?? '',
                            style: TextStyle(
                                color: scheme.onErrorContainer, fontSize: 13),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // AI input bar
          Container(
            padding: EdgeInsets.fromLTRB(
                10, 6, 10, 8 + MediaQuery.of(context).padding.bottom),
            color: scheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.inputCtrl,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: 'Demandez à votre IA…',
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    onSubmitted: widget.thinking ? null : (_) => widget.onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                widget.thinking
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: scheme.primary),
                        ),
                      )
                    : IconButton.filled(
                        icon: const Icon(Icons.send_rounded, size: 18),
                        onPressed: widget.onSend,
                        tooltip: 'Envoyer',
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── AI message row ─────────────────────────────────────────────────────────────

class _AiMessageRow extends StatelessWidget {
  final AiMessage msg;
  final ColorScheme scheme;
  final VoidCallback? onUseInChat;

  const _AiMessageRow({
    required this.msg,
    required this.scheme,
    this.onUseInChat,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: isUser ? scheme.primary : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14).copyWith(
                bottomRight: isUser
                    ? const Radius.circular(3)
                    : const Radius.circular(14),
                bottomLeft: isUser
                    ? const Radius.circular(14)
                    : const Radius.circular(3),
              ),
            ),
            child: SelectableText(
              msg.text,
              style: TextStyle(
                fontSize: 13,
                color:
                    isUser ? scheme.onPrimary : scheme.onSecondaryContainer,
              ),
            ),
          ),
          if (!isUser && onUseInChat != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: GestureDetector(
                onTap: onUseInChat,
                child: Text(
                  'Utiliser dans le chat →',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
  final void Function(String content, String? title)? onExport;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onChallenge,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDocument) {
      return _DocumentCard(
          message: message, onChallenge: onChallenge, onExport: onExport);
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
  final void Function(String content, String? title)? onExport;

  const _DocumentCard({required this.message, this.onChallenge, this.onExport});

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
                  const SizedBox(width: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label:
                        const Text('Exporter', style: TextStyle(fontSize: 13)),
                    onPressed: widget.onExport != null
                        ? () => widget.onExport!(msg.content, msg.documentTitle)
                        : null,
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
  final VoidCallback onAttach;
  final VoidCallback onAiToggle;
  final bool aiPanelOpen;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
    required this.onAiToggle,
    required this.aiPanelOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      padding: EdgeInsets.fromLTRB(
        4,
        8,
        8,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          // AI copilote toggle
          IconButton(
            icon: Text(
              '✦',
              style: TextStyle(
                fontSize: 20,
                color: aiPanelOpen
                    ? scheme.secondary
                    : scheme.onSurface.withOpacity(0.4),
                fontWeight: FontWeight.bold,
              ),
            ),
            tooltip: 'Copilote IA personnel',
            onPressed: onAiToggle,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message…',
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
          const SizedBox(width: 4),
          // Attach document button
          IconButton(
            icon: Icon(Icons.attach_file_rounded,
                size: 22, color: scheme.onSurface.withOpacity(0.5)),
            tooltip: 'Joindre un document',
            onPressed: onAttach,
          ),
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
              'Envoyez un message pour démarrer.\nUtilisez ❖ pour invoquer votre copilote IA privé.',
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

// ── Members bottom sheet ──────────────────────────────────────────────────────

class _MembersSheet extends StatelessWidget {
  final Room room;
  final List<String> onlineUserIds;
  final String myUserId;

  const _MembersSheet({
    required this.room,
    required this.onlineUserIds,
    required this.myUserId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final members = room.members;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(Icons.group_rounded, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Membres du salon',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${members.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Member list
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: members.length,
              itemBuilder: (ctx, i) {
                final m = members[i];
                final isOnline = onlineUserIds.contains(m.userId);
                final isMe = m.userId == myUserId;
                return ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: Text(
                          m.displayName.isNotEmpty
                              ? m.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22c55e),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: scheme.surface, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    m.displayName + (isMe ? ' (moi)' : ''),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isMe ? scheme.primary : null,
                    ),
                  ),
                  subtitle: Text(
                    isOnline ? 'En ligne' : 'Hors ligne',
                    style: TextStyle(
                      fontSize: 11,
                      color: isOnline
                          ? const Color(0xFF22c55e)
                          : scheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Attach document bottom sheet ──────────────────────────────────────────────

class _AttachDocumentSheet extends StatefulWidget {
  final String displayName;
  final Future<void> Function(String title, String content) onUpload;

  const _AttachDocumentSheet({
    required this.displayName,
    required this.onUpload,
  });

  @override
  State<_AttachDocumentSheet> createState() => _AttachDocumentSheetState();
}

class _AttachDocumentSheetState extends State<_AttachDocumentSheet> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _uploading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) return;
    setState(() => _uploading = true);
    try {
      await widget.onUpload(
        _titleCtrl.text.trim().isEmpty
            ? 'Document partagé'
            : _titleCtrl.text.trim(),
        content,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.description_rounded,
                    color: scheme.secondary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Partager un document',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titre (optionnel)',
                hintText: 'Ex: Cahier des charges, Note de synthèse…',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              maxLines: 8,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Contenu *',
                hintText: 'Collez ou saisissez le texte du document…',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _uploading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                    _uploading ? 'Envoi en cours…' : 'Partager le document'),
                onPressed: _uploading ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Web download helper ───────────────────────────────────────────────────────
// Implemented via conditional imports in lib/utils/web_download.dart
// (web_download_web.dart uses dart:html; web_download_stub.dart is a no-op).
