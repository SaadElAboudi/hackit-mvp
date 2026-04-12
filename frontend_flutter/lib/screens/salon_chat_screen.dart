import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/room.dart';
import '../providers/room_provider.dart';
import '../services/project_service.dart' show ProjectService;
import '../utils/web_download.dart';
import 'canvas_screen.dart';
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
      'Rejoins le channel "${room.name}" sur HackIt :\n$link',
      subject: 'Invitation au channel ${room.name}',
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

  void _insertCommand(String command) {
    // Intercept /doc to show a proper creation dialog
    if (command == '/doc') {
      _showCreateDocDialog();
      return;
    }
    final current = _inputCtrl.text.trim();
    final next = current.isEmpty ? '$command ' : '$command $current';
    setState(() {
      _inputCtrl.text = next;
      _inputCtrl.selection = TextSelection.collapsed(offset: next.length);
    });
  }

  Future<void> _showCreateDocDialog() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer un canvas partagé'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Titre',
                hintText: 'Ex: Stratégie go-to-market Q3',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText:
                    'Contenu initial (ou laissez vide pour laisser l\'IA générer)',
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
            onPressed: () =>
                Navigator.pop(ctx, titleCtrl.text.trim().isNotEmpty),
            child: const Text('Créer le canvas'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final title = titleCtrl.text.trim();
      final content = contentCtrl.text.trim();
      // If content is empty, delegate to the AI via /doc command
      if (content.isEmpty) {
        final cmd = '/doc $title';
        setState(() {
          _inputCtrl.text = cmd;
          _inputCtrl.selection = TextSelection.collapsed(offset: cmd.length);
        });
      } else {
        final success =
            await context.read<RoomProvider>().createArtifact(title, content);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Canvas "$title" créé ✓'
              : 'Impossible de créer le canvas'),
        ));
        if (success) _scrollToBottom(animated: true);
      }
    }
  }

  Future<void> _showLaunchMissionDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lancer une mission IA'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText:
                'Ex: Rédige une stratégie go-to-market pour notre produit…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
            child: const Text('Lancer'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      final success =
          await context.read<RoomProvider>().createMission(ctrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Mission lancée ✦' : 'Impossible de lancer la mission',
          ),
        ),
      );
    }
  }

  Future<void> _showReviseArtifactDialog(RoomArtifact artifact) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Réviser "${artifact.title}"'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText:
                'Ex: ajoute les risques, rends le plus concret, prépare une v2 client…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
            child: const Text('Lancer la révision'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      final success = await context
          .read<RoomProvider>()
          .reviseArtifact(artifact.id, ctrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Révision IA lancée' : 'Impossible de lancer la révision',
          ),
        ),
      );
    }
  }

  Widget _buildConversationList(
      RoomProvider prov, Room room, ColorScheme scheme) {
    if (prov.loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    if (prov.messages.isEmpty && !prov.aiThinking) {
      return _EmptyChat(roomName: room.name);
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: prov.messages.length + (prov.aiThinking ? 1 : 0),
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
              ? (content, title) => _exportDocument(content, title)
              : null,
          onOpenCanvas: msg.isArtifact
              ? () {
                  final artifactId = msg.data['artifactId']?.toString() ?? '';
                  if (artifactId.isEmpty) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CanvasScreen(
                        roomId: msg.roomId,
                        artifactId: artifactId,
                        initialTitle: msg.documentTitle,
                      ),
                    ),
                  );
                }
              : null,
        );
      },
    );
  }

  Widget _buildConversationColumn(
    BuildContext context,
    Room room,
    RoomProvider prov,
    ColorScheme scheme, {
    required bool showContextPanel,
  }) {
    return Column(
      children: [
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
        _CommandQuickBar(onInsertCommand: _insertCommand),
        Expanded(child: _buildConversationList(prov, room, scheme)),
        _InputBar(
          controller: _inputCtrl,
          sending: prov.sendingMessage,
          onSend: _send,
          onAttach: _showAttachDialog,
        ),
      ],
    );
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showContextPanel = constraints.maxWidth >= 1080;
          if (!showContextPanel) {
            return _buildConversationColumn(
              context,
              room,
              prov,
              scheme,
              showContextPanel: false,
            );
          }

          return Row(
            children: [
              Expanded(
                flex: 5,
                child: _buildConversationColumn(
                  context,
                  room,
                  prov,
                  scheme,
                  showContextPanel: true,
                ),
              ),
              Container(
                width: 340,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  border: Border(
                    left: BorderSide(
                      color: scheme.outlineVariant.withOpacity(0.35),
                    ),
                  ),
                ),
                child: _ContextPanel(
                  room: room,
                  artifacts: prov.artifacts,
                  memoryItems: prov.memoryItems,
                  missions: prov.missions,
                  onlineUserIds: prov.onlineUserIds,
                  onInsertCommand: _insertCommand,
                  onReviseArtifact: _showReviseArtifactDialog,
                  onLaunchMission: _showLaunchMissionDialog,
                  onOpenCanvas: (artifact) => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CanvasScreen(
                        roomId: artifact.roomId,
                        artifactId: artifact.id,
                        initialTitle: artifact.title,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
                  if (room.purpose.isNotEmpty)
                    Text(
                      room.purpose,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withOpacity(0.45),
                      ),
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
          tooltip: 'Partager le channel',
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

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final RoomMessage message;
  final bool isMe;
  final Future<bool> Function(String)? onChallenge;
  final void Function(String content, String? title)? onExport;
  final VoidCallback? onOpenCanvas;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onChallenge,
    this.onExport,
    this.onOpenCanvas,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _SystemEventChip(message: message);
    }
    if (message.isResearch) {
      return _ResearchCard(message: message);
    }
    if (message.isDecision) {
      return _DecisionCard(message: message);
    }
    if (message.isArtifact) {
      return _ArtifactCard(
        message: message,
        onOpenCanvas: onOpenCanvas,
        onChallenge: onChallenge,
        onExport: onExport,
      );
    }
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

// ── Artifact card (navigates to CanvasScreen) ─────────────────────────────────

class _ArtifactCard extends StatefulWidget {
  final RoomMessage message;
  final VoidCallback? onOpenCanvas;
  final Future<bool> Function(String)? onChallenge;
  final void Function(String content, String? title)? onExport;

  const _ArtifactCard({
    required this.message,
    this.onOpenCanvas,
    this.onChallenge,
    this.onExport,
  });

  @override
  State<_ArtifactCard> createState() => _ArtifactCardState();
}

class _ArtifactCardState extends State<_ArtifactCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msg = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withOpacity(0.22),
          border:
              Border.all(color: scheme.secondary.withOpacity(0.45), width: 1.5),
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
                  Icon(Icons.layers_rounded, size: 18, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.documentTitle ?? 'Canvas partagé',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '❆ Canvas IA • ${msg.challenges.length} challenge${msg.challenges.length != 1 ? 's' : ''}',
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

            // Content preview (collapsible)
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: SelectableText(
                  msg.content,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                  maxLines: 12,
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
              child: Wrap(
                spacing: 4,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.layers_rounded, size: 15),
                    label: const Text('Ouvrir le canvas',
                        style: TextStyle(fontSize: 13)),
                    onPressed: widget.onOpenCanvas,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    icon:
                        const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text('Challenger',
                        style: TextStyle(fontSize: 13)),
                    onPressed: widget.onChallenge != null
                        ? () => _showChallengeDialog(context)
                        : null,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copier', style: TextStyle(fontSize: 13)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: msg.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Copié'),
                            duration: Duration(seconds: 1)),
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
        title: const Text('Challenger ce canvas'),
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
                          msg.documentTitle ??
                              (msg.isAI
                                  ? 'Canvas IA partagé'
                                  : 'Canvas partagé'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${msg.isAI ? '✦ IA' : 'Partagé'} • ${msg.challenges.length} challenge${msg.challenges.length != 1 ? 's' : ''}',
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

// ── System event chip ─────────────────────────────────────────────────────────

class _SystemEventChip extends StatelessWidget {
  final RoomMessage message;
  const _SystemEventChip({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withOpacity(0.55),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Research card ─────────────────────────────────────────────────────────────

class _ResearchCard extends StatelessWidget {
  final RoomMessage message;
  const _ResearchCard({required this.message});

  Future<void> _openSource(BuildContext context, String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir la source')),
      );
    }
  }

  Future<void> _retrySearch(BuildContext context, String query) async {
    if (query.trim().isEmpty) return;
    await context.read<RoomProvider>().sendMessage('/search $query');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final citations =
        (message.data['citations'] as List? ?? []).whereType<Map>().toList();
    final chapters =
        (message.data['chapters'] as List? ?? []).whereType<Map>().toList();
    final alternatives =
        (message.data['alternatives'] as List? ?? []).whereType<Map>().toList();
    final videoTitle = message.data['videoTitle']?.toString() ?? 'Source';
    final videoUrl = message.data['videoUrl']?.toString() ?? '';
    final query = message.data['query']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withOpacity(0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.tertiary.withOpacity(0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.travel_explore_rounded,
                      color: scheme.tertiary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recherche attachée',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                videoTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                message.content,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
              if (videoUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _openSource(context, videoUrl),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      videoUrl,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
              if (citations.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Citations',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 6),
                ...citations.take(3).map(
                      (citation) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () => _openSource(
                              context, citation['url']?.toString() ?? ''),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Text(
                              '• ${citation['quote'] ?? ''}',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: scheme.onSurface,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
              if (chapters.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Chapitres',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chapters.take(4).map((chapter) {
                    final title = chapter['title']?.toString() ?? 'Extrait';
                    final chapterUrl = chapter['url']?.toString() ?? '';
                    return ActionChip(
                      onPressed: chapterUrl.isEmpty
                          ? null
                          : () => _openSource(context, chapterUrl),
                      label: Text(
                        title,
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
              if (alternatives.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Sources alternatives',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 6),
                ...alternatives.take(2).map((alt) {
                  final title = alt['title']?.toString() ?? 'Alternative';
                  final url = alt['url']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: InkWell(
                      onTap:
                          url.isEmpty ? null : () => _openSource(context, url),
                      child: Text(
                        '• $title',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: videoUrl.isEmpty
                        ? null
                        : () => _openSource(context, videoUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Jump to source'),
                  ),
                  OutlinedButton.icon(
                    onPressed: query.isEmpty
                        ? null
                        : () => _retrySearch(context, query),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Relancer /search'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final RoomMessage message;
  const _DecisionCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decisions = (message.data['decisions'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final risks = (message.data['risks'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final nextSteps = (message.data['nextSteps'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    Widget section(String title, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 6),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withOpacity(0.42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withOpacity(0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rule_folder_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Synthèse de décision',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                message.content,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
              section('Décisions', decisions),
              section('Risques', risks),
              section('Next steps', nextSteps),
            ],
          ),
        ),
      ),
    );
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

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
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
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message, @ia, /doc, /search, /decide, /mission…',
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
              'Envoyez un message pour démarrer.\nUtilisez @ia, /doc, /search, /decide ou /mission pour collaborer avec l’IA du channel.',
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

class _CommandQuickBar extends StatelessWidget {
  final void Function(String command) onInsertCommand;

  const _CommandQuickBar({required this.onInsertCommand});

  @override
  Widget build(BuildContext context) {
    final actions = <({String label, String command})>[
      (label: '@ia', command: '@ia'),
      (label: '/doc', command: '/doc'),
      (label: '/search', command: '/search'),
      (label: '/decide', command: '/decide'),
      (label: '/mission', command: '/mission'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: actions.map((action) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton(
                onPressed: () => onInsertCommand(action.command),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(action.label),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ContextPanel extends StatelessWidget {
  final Room room;
  final List<RoomArtifact> artifacts;
  final List<RoomMemory> memoryItems;
  final List<RoomMission> missions;
  final List<String> onlineUserIds;
  final void Function(String command) onInsertCommand;
  final Future<void> Function(RoomArtifact artifact) onReviseArtifact;
  final VoidCallback onLaunchMission;
  final void Function(RoomArtifact artifact) onOpenCanvas;

  const _ContextPanel({
    required this.room,
    required this.artifacts,
    required this.memoryItems,
    required this.missions,
    required this.onlineUserIds,
    required this.onInsertCommand,
    required this.onReviseArtifact,
    required this.onLaunchMission,
    required this.onOpenCanvas,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget sectionTitle(String title, {String? subtitle}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.55),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        sectionTitle(
          'Contexte',
          subtitle: room.purpose.isEmpty
              ? 'Aucune description de channel.'
              : room.purpose,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text('${room.memberCount} membres'),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text('${onlineUserIds.length} en ligne'),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(
                  room.visibility == 'public' ? 'Public' : 'Invitation',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        sectionTitle(
          'Artefacts',
          subtitle:
              artifacts.isEmpty ? 'Aucun canvas partagé pour le moment.' : null,
        ),
        ...artifacts.take(4).map(
              (artifact) => ListTile(
                dense: true,
                leading: Icon(Icons.layers_rounded, color: scheme.secondary),
                title: Text(
                  artifact.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  artifact.currentVersion?.contentPreview ??
                      '${artifact.kind} • ${artifact.status}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpenCanvas(artifact),
                trailing: IconButton(
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  tooltip: 'Réviser avec IA',
                  onPressed: () => onReviseArtifact(artifact),
                ),
              ),
            ),
        sectionTitle(
          'Mémoire',
          subtitle: memoryItems.isEmpty
              ? 'Décisions et faits importants à réinjecter dans l’IA.'
              : null,
        ),
        ...memoryItems.take(5).map(
              (memory) => ListTile(
                dense: true,
                leading: Icon(
                  memory.type == 'decision'
                      ? Icons.task_alt_rounded
                      : Icons.push_pin_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                title: Text(
                  memory.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${memory.type} • ${memory.createdByName}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            ),
        sectionTitle(
          'Missions IA',
          subtitle: missions.isEmpty ? 'Aucune mission récente.' : null,
        ),
        ...missions.take(4).map(
              (mission) => ListTile(
                dense: true,
                leading: Icon(
                  mission.status == 'done'
                      ? Icons.check_circle_outline_rounded
                      : mission.status == 'failed'
                          ? Icons.error_outline_rounded
                          : Icons.timelapse_rounded,
                  size: 18,
                  color: mission.status == 'done'
                      ? Colors.green
                      : mission.status == 'failed'
                          ? scheme.error
                          : scheme.tertiary,
                ),
                title: Text(
                  mission.promptPreview ?? mission.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(mission.status),
              ),
            ),
        sectionTitle('Actions rapides'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => onInsertCommand('/doc'),
                child: const Text('Créer un canvas'),
              ),
              FilledButton.tonal(
                onPressed: () => onInsertCommand('/search'),
                child: const Text('Attacher une recherche'),
              ),
              FilledButton.tonal(
                onPressed: () => onInsertCommand('/decide'),
                child: const Text('Synthèse de décision'),
              ),
              FilledButton.tonal(
                onPressed: onLaunchMission,
                child: const Text('Lancer une mission IA'),
              ),
            ],
          ),
        ),
      ],
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
                  'Membres du channel',
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
