import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/room.dart';
import '../providers/room_provider.dart';
import '../services/api_service.dart';
import '../services/project_service.dart' show ProjectService;
import '../services/room_service.dart';
import '../utils/web_download.dart';
import '../widgets/glass_panel.dart';
import '../widgets/neumorphic_action_button.dart';
import 'artifact_review_screen.dart';
import 'canvas_screen.dart';
import 'profile_screen.dart';
import 'room_tasks_screen.dart';

const String _uiStyle =
    String.fromEnvironment('UI_STYLE', defaultValue: 'glass-neumorph');
const bool _useNeumorphControls = _uiStyle != 'glass-only';

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
  @visibleForTesting
  final Map<String, dynamic>? debugInitialBackendHealth;
  @visibleForTesting
  final bool disableHealthPolling;

  const SalonChatScreen({
    super.key,
    required this.room,
    this.debugInitialBackendHealth,
    this.disableHealthPolling = false,
  });

  @override
  State<SalonChatScreen> createState() => _SalonChatScreenState();
}

class _SalonChatScreenState extends State<SalonChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final RoomProvider _roomProvider;
  Timer? _healthTicker;
  Map<String, dynamic>? _backendHealth;
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
    _roomProvider = context.read<RoomProvider>();
    _backendHealth = widget.debugInitialBackendHealth;
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      _isAtBottom = pos.pixels >= pos.maxScrollExtent - 100;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _roomProvider.openRoom(widget.room);
      if (!widget.disableHealthPolling) {
        await _refreshBackendHealth();
        _healthTicker = Timer.periodic(
          const Duration(seconds: 45),
          (_) => _refreshBackendHealth(),
        );
      }
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _healthTicker?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _roomProvider.closeRoom();
    super.dispose();
  }

  Future<void> _refreshBackendHealth() async {
    try {
      final health = await ApiService.create().pingHealth(
        timeout: const Duration(seconds: 3),
      );
      if (!mounted) return;
      setState(() => _backendHealth = health);
    } catch (_) {
      if (!mounted) return;
      setState(() => _backendHealth = const {'ok': false, 'status': 'down'});
    }
  }

  bool get _isBackendDegraded {
    final h = _backendHealth;
    if (h == null || h.isEmpty) return false;
    final ok = h['ok'] == true || h['status'] == 200 || h['ok'] == null;
    if (!ok) return true;
    final mock = h['mode'] == 'MOCK' || h['mock'] == true;
    final fallback = h['fallback'] == true;
    final gemini = h['gemini'];
    final breaker = gemini is Map && gemini['breakerActive'] == true;
    final operational = gemini is Map ? gemini['operational'] != false : true;
    return mock || fallback || breaker || !operational;
  }

  String get _backendDegradedMessage {
    final h = _backendHealth;
    if (h == null || h.isEmpty) return 'Mode degrade detecte.';
    if (h['status'] == 'down' || h['ok'] == false) {
      return 'Backend temporairement indisponible. Certaines actions peuvent ralentir.';
    }
    final gemini = h['gemini'];
    if (gemini is Map && gemini['breakerActive'] == true) {
      return 'Mode degrade actif: Gemini en protection (circuit breaker).';
    }
    if (h['mode'] == 'MOCK' || h['mock'] == true) {
      return 'Mode degrade actif: backend en mode mock/fallback.';
    }
    return 'Mode degrade detecte. Fonctionnement partiel, sans blocage.';
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
          action: SnackBarAction(
            label: 'Reessayer',
            textColor: Colors.white,
            onPressed: () async {
              final retryOk =
                  await prov.sendMessage(text, displayName: _displayName);
              if (!mounted) return;
              if (retryOk) {
                _isAtBottom = true;
                _scrollToBottom(animated: true);
              }
            },
          ),
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
        SnackBar(
          content: Text(prov.actionError ?? 'Impossible de generer le lien'),
          action: SnackBarAction(label: 'Reessayer', onPressed: _share),
        ),
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
                    : (prov.actionError ??
                        'Erreur lors du partage du document')),
                action: ok
                    ? null
                    : SnackBarAction(
                        label: 'Reessayer',
                        onPressed: () => _showAttachDialog(),
                      ),
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
              : (context.read<RoomProvider>().actionError ??
                  'Impossible de creer le canvas')),
          action: success
              ? null
              : SnackBarAction(
                  label: 'Reessayer',
                  onPressed: _showCreateDocDialog,
                ),
        ));
        if (success) _scrollToBottom(animated: true);
      }
    }
  }

  Future<void> _showLaunchMissionDialog() async {
    final ctrl = TextEditingController();
    String selectedAgent = 'auto';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Lancer une mission IA'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedAgent,
                decoration: const InputDecoration(
                  labelText: 'Agent spécialisé',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                  DropdownMenuItem(
                      value: 'strategist', child: Text('Strategist')),
                  DropdownMenuItem(
                      value: 'researcher', child: Text('Researcher')),
                  DropdownMenuItem(
                      value: 'facilitator', child: Text('Facilitator')),
                  DropdownMenuItem(value: 'analyst', child: Text('Analyst')),
                  DropdownMenuItem(value: 'writer', child: Text('Writer')),
                ],
                onChanged: (value) =>
                    setState(() => selectedAgent = value ?? 'auto'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText:
                      'Ex: Rédige une stratégie go-to-market pour notre produit…',
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
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
              child: const Text('Lancer'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      final success = await context.read<RoomProvider>().createMission(
            ctrl.text.trim(),
            agentType: selectedAgent,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Mission lancée avec ${selectedAgent == 'auto' ? 'agent auto' : selectedAgent} ✦'
                : (context.read<RoomProvider>().actionError ??
                    'Impossible de lancer la mission'),
          ),
          action: success
              ? null
              : SnackBarAction(
                  label: 'Reessayer',
                  onPressed: _showLaunchMissionDialog,
                ),
        ),
      );
    }
  }

  Future<void> _showMissionExtractionDialog(RoomMission mission) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final preview = await prov.previewMissionExtraction(mission.id);
    if (!mounted) return;
    if (preview == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(prov.actionError ?? 'Extraction impossible')),
      );
      return;
    }

    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Extraire decisions et taches'),
          content: SizedBox(
            width: 520,
            child: preview.extracted.isEmpty
                ? const Text(
                    'Aucune decision exploitable detectee pour cette mission.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mission.promptPreview ?? mission.prompt,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        ...preview.extracted.map(
                          (decision) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  decision.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                if (decision.summary.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(decision.summary),
                                ],
                                if (decision.tasks.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ...decision.tasks.map(
                                    (task) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('• '),
                                          Expanded(
                                            child: Text(
                                              task.description.isEmpty
                                                  ? task.title
                                                  : '${task.title} — ${task.description}',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: saving || preview.extracted.isEmpty
                  ? null
                  : () async {
                      setState(() => saving = true);
                      final persisted =
                          await prov.persistMissionExtraction(mission.id);
                      if (!mounted || !ctx.mounted) return;
                      if (persisted == null) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              prov.actionError ??
                                  'Impossible de persister l\'extraction',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${persisted.decisions.length} decision(s) et ${persisted.tasks.length} tache(s) creees',
                          ),
                        ),
                      );
                    },
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(saving ? 'Creation...' : 'Creer les taches'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTaskEditDialog(WorkspaceTask task) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ownerCtrl = TextEditingController(text: task.ownerName);
    String status = task.status;
    DateTime? dueDate = task.dueDate;
    bool clearDueDate = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Mettre a jour la tache'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(task.description),
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Statut',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'todo', child: Text('A faire')),
                    DropdownMenuItem(
                      value: 'in_progress',
                      child: Text('En cours'),
                    ),
                    DropdownMenuItem(
                      value: 'blocked',
                      child: Text('Bloquee'),
                    ),
                    DropdownMenuItem(value: 'done', child: Text('Terminee')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) =>
                          setState(() => status = value ?? task.status),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ownerCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Responsable',
                    hintText: 'Nom du responsable',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: saving
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: dueDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 3650),
                            ),
                          );
                          if (picked == null || !ctx.mounted) return;
                          setState(() {
                            dueDate = picked;
                            clearDueDate = false;
                          });
                        },
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Echeance',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dueDate == null || clearDueDate
                                ? 'Aucune date'
                                : '${dueDate!.day.toString().padLeft(2, '0')}/${dueDate!.month.toString().padLeft(2, '0')}/${dueDate!.year}',
                          ),
                        ),
                        if (dueDate != null && !clearDueDate)
                          IconButton(
                            onPressed: saving
                                ? null
                                : () => setState(() {
                                      clearDueDate = true;
                                      dueDate = null;
                                    }),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Retirer la date',
                          )
                        else
                          const Icon(Icons.event_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      final updated = await prov.updateTask(
                        task,
                        status: status,
                        ownerName: ownerCtrl.text.trim(),
                        ownerId:
                            ownerCtrl.text.trim().isEmpty ? '' : task.ownerId,
                        dueDate: dueDate,
                        clearDueDate: clearDueDate,
                      );
                      if (!mounted || !ctx.mounted) return;
                      if (updated == null) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              prov.actionError ??
                                  'Impossible de mettre a jour la tache',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Tache mise a jour')),
                      );
                    },
              child: Text(saving ? 'Mise a jour...' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSlackIntegrationDialog() async {
    final prov = context.read<RoomProvider>();
    final status = prov.slackIntegration;
    final tokenCtrl = TextEditingController();
    final channelCtrl = TextEditingController(text: status?.channelId ?? '');
    final messenger = ScaffoldMessenger.of(context);
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Connecter Slack'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tokenCtrl,
                  enabled: !saving,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Bot token *',
                    hintText: 'xoxb-...',
                    helperText: 'Token bot Slack requis (prefixe xoxb-)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: channelCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Channel ID *',
                    hintText: 'C012AB3CD',
                    helperText: 'ID channel Slack (prefixe C... ou G...)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final botToken = tokenCtrl.text.trim();
                      final channelId = channelCtrl.text.trim();
                      if (botToken.isEmpty || channelId.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Token et channel sont requis'),
                          ),
                        );
                        return;
                      }
                      if (!botToken.startsWith('xoxb-')) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content:
                                Text('Le token Slack doit commencer par xoxb-'),
                          ),
                        );
                        return;
                      }
                      if (!RegExp(r'^[CG][A-Z0-9]{6,}$').hasMatch(channelId)) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content:
                                Text('Channel ID invalide (ex: C012AB3CD)'),
                          ),
                        );
                        return;
                      }
                      setState(() => saving = true);
                      final ok = await prov.connectSlackIntegration(
                        botToken: botToken,
                        channelId: channelId,
                      );
                      if (!mounted || !ctx.mounted) return;
                      if (!ok) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              prov.actionError ?? 'Connexion Slack impossible',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Slack connecte')),
                      );
                    },
              child: Text(saving ? 'Connexion...' : 'Connecter'),
            ),
          ],
        ),
      ),
    );

    tokenCtrl.dispose();
    channelCtrl.dispose();
  }

  Future<void> _showNotionIntegrationDialog() async {
    final prov = context.read<RoomProvider>();
    final status = prov.notionIntegration;
    final tokenCtrl = TextEditingController();
    final queryCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    List<NotionPageOption> pages = const [];
    String selectedPageId = status?.parentPageId ?? '';
    bool loadingPages = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Connecter Notion'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tokenCtrl,
                  enabled: !saving,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API token *',
                    hintText: 'secret_... ou ntn_...',
                    helperText:
                        'Token integration Notion (secret_... ou ntn_...)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: queryCtrl,
                  enabled: !saving && !loadingPages,
                  decoration: const InputDecoration(
                    labelText: 'Recherche de pages (optionnel)',
                    hintText: 'Ex: Marketing, Product roadmap...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: saving || loadingPages
                        ? null
                        : () async {
                            final apiToken = tokenCtrl.text.trim();
                            if (apiToken.isEmpty) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Renseigne d\'abord le token Notion',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (!(apiToken.startsWith('secret_') ||
                                apiToken.startsWith('ntn_'))) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Le token Notion doit commencer par secret_ ou ntn_',
                                  ),
                                ),
                              );
                              return;
                            }

                            setState(() => loadingPages = true);
                            final fetched = await prov.discoverNotionPages(
                              apiToken: apiToken,
                              query: queryCtrl.text.trim(),
                              limit: 30,
                            );
                            if (!mounted || !ctx.mounted) return;
                            setState(() {
                              pages = fetched;
                              final hasSelected = pages
                                  .any((page) => page.id == selectedPageId);
                              if (!hasSelected) {
                                selectedPageId =
                                    pages.isNotEmpty ? pages.first.id : '';
                              }
                              loadingPages = false;
                            });

                            if (fetched.isEmpty) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    prov.actionError ??
                                        'Aucune page accessible trouvee',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: loadingPages
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore_rounded, size: 16),
                    label: Text(
                      loadingPages ? 'Chargement...' : 'Charger mes pages',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: pages.any((p) => p.id == selectedPageId)
                      ? selectedPageId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Page parent Notion *',
                    helperText: 'Choisis la page cible pour les exports',
                    border: OutlineInputBorder(),
                  ),
                  items: pages
                      .map(
                        (page) => DropdownMenuItem<String>(
                          value: page.id,
                          child: Text(
                            page.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving || loadingPages
                      ? null
                      : (value) => setState(() => selectedPageId = value ?? ''),
                ),
                if (pages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Charge d\'abord les pages accessibles avec ton token, puis selectionne-en une.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.62),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final apiToken = tokenCtrl.text.trim();
                      final parentPageId = selectedPageId.trim();
                      if (apiToken.isEmpty || parentPageId.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Token requis et page parent a selectionner',
                            ),
                          ),
                        );
                        return;
                      }
                      if (!(apiToken.startsWith('secret_') ||
                          apiToken.startsWith('ntn_'))) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Le token Notion doit commencer par secret_ ou ntn_',
                            ),
                          ),
                        );
                        return;
                      }
                      setState(() => saving = true);
                      final ok = await prov.connectNotionIntegration(
                        apiToken: apiToken,
                        parentPageId: parentPageId,
                      );
                      if (!mounted || !ctx.mounted) return;
                      if (!ok) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              prov.actionError ?? 'Connexion Notion impossible',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Notion connecte')),
                      );
                    },
              child: Text(saving ? 'Connexion...' : 'Connecter'),
            ),
          ],
        ),
      ),
    );

    tokenCtrl.dispose();
    queryCtrl.dispose();
  }

  Future<void> _disconnectSlackIntegration() async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Deconnecter Slack ?'),
            content: const Text(
              'Les prochains partages Slack seront bloques tant que la connexion n\'est pas reconfiguree.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Deconnecter'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final ok = await prov.disconnectSlackIntegration();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Slack deconnecte' : (prov.actionError ?? 'Action impossible'),
        ),
      ),
    );
  }

  Future<void> _disconnectNotionIntegration() async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Deconnecter Notion ?'),
            content: const Text(
              'Les prochains exports Notion seront bloques tant que la connexion n\'est pas reconfiguree.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Deconnecter'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final ok = await prov.disconnectNotionIntegration();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Notion deconnecte' : (prov.actionError ?? 'Action impossible'),
        ),
      ),
    );
  }

  Future<void> _shareToIntegration({
    required String target,
    required String label,
  }) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await prov.shareToIntegration(target: target);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Partage envoye vers $label'
              : (prov.actionError ?? 'Partage impossible vers $label'),
        ),
      ),
    );
  }

  Future<void> _openDecisionPack({String mode = 'checklist'}) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await prov.loadDecisionPack(mode: mode);
    if (!mounted) return;
    if (!ok || prov.decisionPack == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(prov.actionError ?? 'Decision Pack indisponible')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Decision Pack (${prov.decisionPack!.pack.mode})'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: SelectableText(prov.decisionPack!.pack.markdown),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDecisionPack({
    required String target,
    required String label,
    String mode = 'executive',
  }) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await prov.shareDecisionPack(target: target, mode: mode);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Decision Pack partage vers $label'
              : (prov.actionError ?? 'Partage Decision Pack impossible'),
        ),
      ),
    );
  }

  Future<void> _refreshDecisionPackAggregate([int sinceDays = 14]) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await prov.refreshDecisionPackAggregate(sinceDays: sinceDays);
    if (!mounted || ok) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          prov.actionError ?? 'Impossible de charger les KPI Decision Pack',
        ),
      ),
    );
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
            success
                ? 'Revision IA lancee'
                : (context.read<RoomProvider>().actionError ??
                    'Impossible de lancer la revision'),
          ),
          action: success
              ? null
              : SnackBarAction(
                  label: 'Reessayer',
                  onPressed: () => _showReviseArtifactDialog(artifact),
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

    if (prov.messagesError != null && prov.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 34),
              const SizedBox(height: 10),
              Text(
                prov.messagesError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => prov.openRoom(room),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Recharger'),
              ),
            ],
          ),
        ),
      );
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
          onInsertCommand: _insertCommand,
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
        if (_isBackendDegraded)
          Container(
            color: Colors.amber.shade700,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _backendDegradedMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _refreshBackendHealth,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Actualiser'),
                ),
              ],
            ),
          ),
        _CommandQuickBar(
          onInsertCommand: _insertCommand,
          useNeumorphControls: _useNeumorphControls,
        ),
        if (prov.actionError != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.error.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prov.actionError!,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (prov.actionContext != null &&
                        prov.actionContext!.isNotEmpty)
                      Text(
                        'Contexte: ${prov.actionContext}',
                        style: TextStyle(
                          color:
                              scheme.onErrorContainer.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    if (prov.actionRequestId != null &&
                        prov.actionRequestId!.isNotEmpty)
                      GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: prov.actionRequestId!),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Request ID copie')),
                          );
                        },
                        child: Text(
                          'requestId: ${prov.actionRequestId}',
                          style: TextStyle(
                            color:
                                scheme.onErrorContainer.withValues(alpha: 0.85),
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (prov.canRetryLastAction)
                      FilledButton.tonal(
                        onPressed: prov.retryingLastAction
                            ? null
                            : () async {
                                final ok = await prov.retryLastAction();
                                if (!context.mounted || ok) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      prov.actionError ??
                                          'Nouvelle tentative en echec',
                                    ),
                                  ),
                                );
                              },
                        child: Text(
                          prov.retryingLastAction ? 'Reessai...' : 'Reessayer',
                        ),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: prov.clearActionError,
                      child: const Text('Masquer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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

  Widget _buildWorkspaceContextPanel(
    BuildContext context,
    Room room,
    RoomProvider prov,
  ) {
    final canManageIntegrations =
        _myUserId.isNotEmpty && room.ownerId == _myUserId;

    return _ContextPanel(
      room: room,
      artifacts: prov.artifacts,
      memoryItems: prov.memoryItems,
      missions: prov.missions,
      decisions: prov.decisions,
      tasks: prov.tasks,
      slackIntegration: prov.slackIntegration,
      notionIntegration: prov.notionIntegration,
      shareHistory: prov.shareHistory,
      loadingIntegrations: prov.loadingIntegrations,
      loadingShareHistory: prov.loadingShareHistory,
      decisionPackAggregate: prov.decisionPackAggregate,
      loadingDecisionPackAggregate: prov.loadingDecisionPackAggregate,
      onlineUserIds: prov.onlineUserIds,
      useNeumorphControls: _useNeumorphControls,
      canManageIntegrations: canManageIntegrations,
      onInsertCommand: _insertCommand,
      onReviseArtifact: _showReviseArtifactDialog,
      onLaunchMission: _showLaunchMissionDialog,
      onExtractMission: _showMissionExtractionDialog,
      onEditTask: _showTaskEditDialog,
      onOpenTaskBoard: _openTaskBoard,
      onConnectSlackIntegration: _showSlackIntegrationDialog,
      onDisconnectSlackIntegration: _disconnectSlackIntegration,
      onConnectNotionIntegration: _showNotionIntegrationDialog,
      onDisconnectNotionIntegration: _disconnectNotionIntegration,
      onShareToSlack: () =>
          _shareToIntegration(target: 'slack', label: 'Slack'),
      onShareToNotion: () =>
          _shareToIntegration(target: 'notion', label: 'Notion'),
      onOpenDecisionPackChecklist: () => _openDecisionPack(mode: 'checklist'),
      onOpenDecisionPackExecutive: () => _openDecisionPack(mode: 'executive'),
      onShareDecisionPackToSlack: () =>
          _shareDecisionPack(target: 'slack', label: 'Slack'),
      onShareDecisionPackToNotion: () =>
          _shareDecisionPack(target: 'notion', label: 'Notion'),
      onRefreshIntegrations: prov.refreshIntegrationStatus,
      onRefreshShareHistory: () => prov.refreshShareHistory(),
      onRefreshDecisionPackAggregate: _refreshDecisionPackAggregate,
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
    );
  }

  Future<void> _openTaskBoard() async {
    final prov = context.read<RoomProvider>();
    final room = prov.currentRoom ?? widget.room;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomTasksScreen(
          roomName: room.name,
          onEditTask: _showTaskEditDialog,
        ),
      ),
    );
  }

  Future<void> _showWorkspacePanel() async {
    final prov = context.read<RoomProvider>();
    final room = prov.currentRoom ?? widget.room;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        maxChildSize: 0.96,
        minChildSize: 0.55,
        builder: (_, __) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    color: Theme.of(ctx).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Workspace',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<RoomProvider>(
                builder: (ctx, sheetProv, _) =>
                    _buildWorkspaceContextPanel(ctx, room, sheetProv),
              ),
            ),
          ],
        ),
      ),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.08),
              scheme.surface,
              scheme.tertiary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: LayoutBuilder(
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
                SizedBox(
                  width: 340,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                    child: GlassPanel(
                      borderRadius: BorderRadius.circular(18),
                      child: _buildWorkspaceContextPanel(context, room, prov),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, Room room, ColorScheme scheme) {
    final prov = context.watch<RoomProvider>();
    final onlineCount = prov.onlineUserIds.length;
    final showWorkspaceButton = MediaQuery.sizeOf(context).width < 1080;

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
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  Row(
                    children: [
                      Text(
                        '${room.memberCount} membre${room.memberCount > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.5),
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
                            color: scheme.onSurface.withValues(alpha: 0.5),
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
        IconButton(
          icon: const Icon(Icons.view_kanban_outlined),
          tooltip: 'Board des taches',
          onPressed: _openTaskBoard,
        ),
        if (showWorkspaceButton)
          IconButton(
            icon: const Icon(Icons.dashboard_customize_outlined),
            tooltip: 'Workspace',
            onPressed: _showWorkspacePanel,
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
  final void Function(String command)? onInsertCommand;
  final Future<bool> Function(String)? onChallenge;
  final void Function(String content, String? title)? onExport;
  final VoidCallback? onOpenCanvas;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onInsertCommand,
    this.onChallenge,
    this.onExport,
    this.onOpenCanvas,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      if (message.data['kind']?.toString() == 'meeting_brief') {
        return _MeetingBriefCard(
          message: message,
          onInsertCommand: onInsertCommand,
        );
      }
      if (message.data['kind']?.toString() == 'synthesis_suggestion') {
        return _SynthesisSuggestionCard(
          message: message,
          onInsertCommand: onInsertCommand,
        );
      }
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
    final trust = _TrustPayload.fromMessage(message);

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
                            : scheme.onSurface.withValues(alpha: 0.6),
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
                if (trust != null) ...[
                  const SizedBox(height: 6),
                  _TrustExplainabilityBlock(trust: trust),
                ],
                if (isAI)
                  _AiFeedbackRow(
                    message: message,
                    onRate: (rating, {reason}) {
                      context.read<RoomProvider>().submitMessageFeedback(
                        messageId: message.id,
                        rating: rating,
                        reason: reason,
                        metadata: const {
                          'source': 'chat',
                          'surface': 'salon',
                        },
                      );
                    },
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

class _TrustPayload {
  final String confidence;
  final String whyThisPlan;
  final List<String> assumptions;
  final List<String> limits;

  const _TrustPayload({
    required this.confidence,
    required this.whyThisPlan,
    required this.assumptions,
    required this.limits,
  });

  static _TrustPayload? fromMessage(RoomMessage message) {
    final raw = message.data['trust'];
    if (raw is! Map) return null;

    final confidence = raw['confidence']?.toString().trim() ?? '';
    final whyThisPlan = raw['whyThisPlan']?.toString().trim() ?? '';
    final assumptions = (raw['assumptions'] as List? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
    final limits = (raw['limits'] as List? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();

    if (confidence.isEmpty &&
        whyThisPlan.isEmpty &&
        assumptions.isEmpty &&
        limits.isEmpty) {
      return null;
    }

    return _TrustPayload(
      confidence: confidence,
      whyThisPlan: whyThisPlan,
      assumptions: assumptions,
      limits: limits,
    );
  }
}

class _TrustExplainabilityBlock extends StatelessWidget {
  final _TrustPayload trust;

  const _TrustExplainabilityBlock({required this.trust});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confidenceLabel = trust.confidence.isEmpty
        ? 'n/a'
        : trust.confidence[0].toUpperCase() + trust.confidence.substring(1);

    Widget section(String label, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 4),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '- $item',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.78),
                    height: 1.28,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 14, color: scheme.tertiary),
              const SizedBox(width: 6),
              Text(
                'Pourquoi ce plan',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                'Confiance: $confidenceLabel',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),
          if (trust.whyThisPlan.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              trust.whyThisPlan,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: scheme.onSurface.withValues(alpha: 0.86),
              ),
            ),
          ],
          section('Hypotheses', trust.assumptions),
          section('Limites', trust.limits),
        ],
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
      child: GlassPanel(
        tint: scheme.secondaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
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
                            color: scheme.onSurface.withValues(alpha: 0.5),
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
                    color: scheme.onSurface.withValues(alpha: 0.6),
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
                          size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${c.userName}: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha: 0.7),
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
                color:
                    Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
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
      child: GlassPanel(
        tint: scheme.surfaceContainerLow.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(16),
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
                            color: scheme.onSurface.withValues(alpha: 0.5),
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
                    color: scheme.onSurface.withValues(alpha: 0.6),
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
                          size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${c.userName}: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha: 0.7),
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
                color:
                    Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
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

class _SynthesisSuggestionCard extends StatelessWidget {
  final RoomMessage message;
  final void Function(String command)? onInsertCommand;

  const _SynthesisSuggestionCard({
    required this.message,
    this.onInsertCommand,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final basedOn =
        int.tryParse(message.data['basedOnMessages']?.toString() ?? '') ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        tint: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Suggestion automatique de synthèse',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                if (basedOn > 0)
                  Text(
                    '$basedOn msgs',
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.55)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              message.content,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onInsertCommand == null
                      ? null
                      : () => onInsertCommand!('/decide'),
                  icon: const Icon(Icons.rule_folder_rounded, size: 16),
                  label: const Text('Transformer en /decide'),
                ),
                OutlinedButton.icon(
                  onPressed: onInsertCommand == null
                      ? null
                      : () => onInsertCommand!('/doc'),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Transformer en /doc'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingBriefCard extends StatelessWidget {
  final RoomMessage message;
  final void Function(String command)? onInsertCommand;

  const _MeetingBriefCard({
    required this.message,
    this.onInsertCommand,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final objective = message.data['objective']?.toString() ?? '';
    final basedOn =
        int.tryParse(message.data['basedOnMessages']?.toString() ?? '') ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        tint: scheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_rounded, size: 18, color: scheme.tertiary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Brief automatique avant réunion',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                if (basedOn > 0)
                  Text(
                    '$basedOn msgs',
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.55)),
                  ),
              ],
            ),
            if (objective.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Objectif: $objective',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.75)),
              ),
            ],
            const SizedBox(height: 10),
            SelectableText(
              message.content,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onInsertCommand == null
                      ? null
                      : () => onInsertCommand!('/decide'),
                  icon: const Icon(Icons.rule_folder_rounded, size: 16),
                  label: const Text('Valider via /decide'),
                ),
                OutlinedButton.icon(
                  onPressed: onInsertCommand == null
                      ? null
                      : () => onInsertCommand!('/doc'),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Convertir en /doc'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
              color: scheme.onSurface.withValues(alpha: 0.55),
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

  Future<void> _sendFeedback(
    BuildContext context, {
    required bool useful,
  }) async {
    try {
      await roomService.sendSearchFeedback(
        requestId: message.id,
        clicked: useful,
        completed: useful,
        rating: useful ? 5 : 2,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(useful
              ? 'Merci, feedback positif enregistré'
              : 'Feedback enregistré, on améliore la recherche'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      // Keep UX silent on analytics failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trust = _TrustPayload.fromMessage(message);
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
      child: GlassPanel(
        tint: scheme.tertiaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        child: Padding(
          padding: EdgeInsets.zero,
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
              if (trust != null) ...[
                const SizedBox(height: 10),
                _TrustExplainabilityBlock(trust: trust),
              ],
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
                    color: scheme.onSurface.withValues(alpha: 0.6),
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
                    color: scheme.onSurface.withValues(alpha: 0.6),
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
                    color: scheme.onSurface.withValues(alpha: 0.6),
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
                  OutlinedButton.icon(
                    onPressed: () => _sendFeedback(context, useful: true),
                    icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                    label: const Text('Utile'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _sendFeedback(context, useful: false),
                    icon: const Icon(Icons.thumb_down_alt_outlined, size: 16),
                    label: const Text('Pas utile'),
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
    final trust = _TrustPayload.fromMessage(message);
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
                color: scheme.onSurface.withValues(alpha: 0.6),
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
      child: GlassPanel(
        tint: scheme.primaryContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        child: Padding(
          padding: EdgeInsets.zero,
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
              if (trust != null) ...[
                const SizedBox(height: 10),
                _TrustExplainabilityBlock(trust: trust),
              ],
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

// ── AI feedback row (pertinent / moyen / hors-sujet) ─────────────────────────

class _AiFeedbackRow extends StatefulWidget {
  final RoomMessage message;
  final void Function(int rating, {String? reason}) onRate;

  const _AiFeedbackRow({required this.message, required this.onRate});

  @override
  State<_AiFeedbackRow> createState() => _AiFeedbackRowState();
}

class _AiFeedbackRowState extends State<_AiFeedbackRow> {
  Future<void> _promptOptionalReasonAndSubmit(int rating) async {
    if (rating == 1) {
      widget.onRate(1);
      return;
    }

    final controller = TextEditingController();
    String? reason;

    try {
      reason = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ajouter un detail (optionnel)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLength: 240,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText:
                        'Ex: trop general, manque de contexte, hors sujet...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(''),
                      child: const Text('Passer'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(ctx).pop(controller.text.trim()),
                      child: const Text('Envoyer'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }

    widget.onRate(rating,
        reason: (reason ?? '').trim().isEmpty ? null : reason!.trim());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;
    final activeLabel = message.userRatingLabel;

    Widget pill({
      required String label,
      required int value,
      required Color activeColor,
      required IconData icon,
      int? count,
    }) {
      final active = activeLabel == label;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _promptOptionalReasonAndSubmit(value),
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? activeColor.withValues(alpha: 0.16)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            border: Border.all(
              color: active
                  ? activeColor.withValues(alpha: 0.7)
                  : scheme.outline.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? activeColor
                    : scheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                label == 'hors_sujet' ? 'Hors sujet' : _capitalize(label),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? activeColor
                      : scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: active
                        ? activeColor
                        : scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2),
      child: Wrap(
        spacing: 0,
        runSpacing: 4,
        children: [
          pill(
            label: 'pertinent',
            value: 1,
            activeColor: Colors.green.shade700,
            icon: Icons.thumb_up_alt_rounded,
            count: message.thumbsUp,
          ),
          pill(
            label: 'moyen',
            value: 0,
            activeColor: Colors.amber.shade800,
            icon: Icons.horizontal_rule_rounded,
          ),
          pill(
            label: 'hors_sujet',
            value: -1,
            activeColor: Colors.red.shade500,
            icon: Icons.thumb_down_alt_rounded,
            count: message.thumbsDown,
          ),
        ],
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
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
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.7),
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
                size: 22, color: scheme.onSurface.withValues(alpha: 0.5)),
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
                color: scheme.onSurface.withValues(alpha: 0.55),
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
  final bool useNeumorphControls;

  const _CommandQuickBar({
    required this.onInsertCommand,
    required this.useNeumorphControls,
  });

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
              child: useNeumorphControls
                  ? NeumorphicActionButton(
                      label: action.label,
                      onPressed: () => onInsertCommand(action.command),
                    )
                  : OutlinedButton(
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
  final List<WorkspaceDecision> decisions;
  final List<WorkspaceTask> tasks;
  final RoomIntegrationStatus? slackIntegration;
  final RoomIntegrationStatus? notionIntegration;
  final List<RoomShareHistoryItem> shareHistory;
  final bool loadingIntegrations;
  final bool loadingShareHistory;
  final DecisionPackAggregate? decisionPackAggregate;
  final bool loadingDecisionPackAggregate;
  final List<String> onlineUserIds;
  final bool useNeumorphControls;
  final bool canManageIntegrations;
  final void Function(String command) onInsertCommand;
  final Future<void> Function(RoomArtifact artifact) onReviseArtifact;
  final VoidCallback onLaunchMission;
  final Future<void> Function(RoomMission mission) onExtractMission;
  final Future<void> Function(WorkspaceTask task) onEditTask;
  final Future<void> Function() onOpenTaskBoard;
  final Future<void> Function() onConnectSlackIntegration;
  final Future<void> Function() onDisconnectSlackIntegration;
  final Future<void> Function() onConnectNotionIntegration;
  final Future<void> Function() onDisconnectNotionIntegration;
  final Future<void> Function() onShareToSlack;
  final Future<void> Function() onShareToNotion;
  final Future<void> Function() onOpenDecisionPackChecklist;
  final Future<void> Function() onOpenDecisionPackExecutive;
  final Future<void> Function() onShareDecisionPackToSlack;
  final Future<void> Function() onShareDecisionPackToNotion;
  final Future<void> Function() onRefreshIntegrations;
  final Future<void> Function() onRefreshShareHistory;
  final Future<void> Function(int sinceDays) onRefreshDecisionPackAggregate;
  final void Function(RoomArtifact artifact) onOpenCanvas;

  const _ContextPanel({
    required this.room,
    required this.artifacts,
    required this.memoryItems,
    required this.missions,
    required this.decisions,
    required this.tasks,
    required this.slackIntegration,
    required this.notionIntegration,
    required this.shareHistory,
    required this.loadingIntegrations,
    required this.loadingShareHistory,
    required this.decisionPackAggregate,
    required this.loadingDecisionPackAggregate,
    required this.onlineUserIds,
    required this.useNeumorphControls,
    required this.canManageIntegrations,
    required this.onInsertCommand,
    required this.onReviseArtifact,
    required this.onLaunchMission,
    required this.onExtractMission,
    required this.onEditTask,
    required this.onOpenTaskBoard,
    required this.onConnectSlackIntegration,
    required this.onDisconnectSlackIntegration,
    required this.onConnectNotionIntegration,
    required this.onDisconnectNotionIntegration,
    required this.onShareToSlack,
    required this.onShareToNotion,
    required this.onOpenDecisionPackChecklist,
    required this.onOpenDecisionPackExecutive,
    required this.onShareDecisionPackToSlack,
    required this.onShareDecisionPackToNotion,
    required this.onRefreshIntegrations,
    required this.onRefreshShareHistory,
    required this.onRefreshDecisionPackAggregate,
    required this.onOpenCanvas,
  });

  String _timeAgo(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return 'a l\'instant';
    if (delta.inHours < 1) return 'il y a ${delta.inMinutes} min';
    if (delta.inDays < 1) return 'il y a ${delta.inHours} h';
    return 'il y a ${delta.inDays} j';
  }

  String _dueLabel(DateTime? at) {
    if (at == null) return '';
    return '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year}';
  }

  // Returns the subtitle for an integration tile using share history
  // (last sync time or last failure reason), falling back to connectedAt.
  String _integrationSubtitle(String target, RoomIntegrationStatus? status) {
    final key = target.toLowerCase();
    // Most recent history entry for this target (list is newest-first from API)
    final last = shareHistory.where((h) => h.target == key).firstOrNull;
    if (last != null) {
      if (last.isFailed) {
        final reason = last.errorCode.isNotEmpty
            ? last.errorCode
            : last.errorMessage.isNotEmpty
                ? last.errorMessage
                : 'Erreur inconnue';
        return 'Echec · $reason · ${_timeAgo(last.createdAt)}';
      }
      if (last.isSuccess) {
        final who = last.actorName.isNotEmpty ? last.actorName : 'inconnu';
        return 'Dernier partage  $who · ${_timeAgo(last.createdAt)}';
      }
    }
    if (status == null || status.connectedAt == null) {
      return 'Aucune synchronisation recente.';
    }
    final who = status.connectedBy.isEmpty ? 'inconnu' : status.connectedBy;
    return 'Connecte par $who · ${_timeAgo(status.connectedAt!)}';
  }

  // Returns the trailing icon color for an integration tile.
  Color _integrationTrailingColor(
    String target,
    bool connected,
    ColorScheme scheme,
  ) {
    final key = target.toLowerCase();
    final last = shareHistory.where((h) => h.target == key).firstOrNull;
    if (last != null && last.isFailed) return Colors.orange;
    if (connected) return Colors.green;
    return scheme.error;
  }

  IconData _integrationTrailingIcon(String target, bool connected) {
    final key = target.toLowerCase();
    final last = shareHistory.where((h) => h.target == key).firstOrNull;
    if (last != null && last.isFailed) return Icons.warning_amber_rounded;
    return connected
        ? Icons.check_circle_outline_rounded
        : Icons.error_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final workArtifacts = artifacts.where((a) => a.kind != 'research').toList();
    final researchArtifacts =
        artifacts.where((a) => a.kind == 'research').toList();

    Widget sectionTitle(String title, {String? subtitle, Widget? trailing}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
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
          subtitle: workArtifacts.isEmpty
              ? 'Aucun canvas partagé pour le moment.'
              : null,
        ),
        ...workArtifacts.take(4).map(
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      tooltip: 'Revue',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ArtifactReviewScreen(artifact: artifact),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                      tooltip: 'Réviser avec IA',
                      onPressed: () => onReviseArtifact(artifact),
                    ),
                  ],
                ),
              ),
            ),
        sectionTitle(
          'Recherches',
          subtitle: researchArtifacts.isEmpty
              ? 'Aucune recherche attachée récemment.'
              : null,
        ),
        if (researchArtifacts.length > 4)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openResearchHistorySheet(
                  context,
                  researchArtifacts,
                  onOpenCanvas,
                ),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: const Text('Voir tout'),
              ),
            ),
          ),
        ...researchArtifacts.take(4).map(
              (artifact) => ListTile(
                dense: true,
                leading:
                    Icon(Icons.travel_explore_rounded, color: scheme.tertiary),
                title: Text(
                  artifact.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  artifact.currentVersion?.contentPreview ??
                      'research • ${artifact.status}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpenCanvas(artifact),
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
                    color: scheme.onSurface.withValues(alpha: 0.5),
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
                subtitle: Text('${mission.agentLabel} · ${mission.status}'),
                trailing: mission.status == 'done'
                    ? IconButton(
                        tooltip: 'Extraire decisions et taches',
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        onPressed: () => onExtractMission(mission),
                      )
                    : null,
              ),
            ),
        sectionTitle(
          'Decisions',
          subtitle: decisions.isEmpty
              ? 'Aucune decision structuree pour le moment.'
              : null,
          trailing: Wrap(
            spacing: 6,
            children: [
              TextButton(
                onPressed: onOpenDecisionPackChecklist,
                child: const Text('Pack checklist'),
              ),
              TextButton(
                onPressed: onOpenDecisionPackExecutive,
                child: const Text('Pack executive'),
              ),
            ],
          ),
        ),
        ...decisions.take(4).map(
              (decision) => ListTile(
                dense: true,
                leading: Icon(
                  Icons.rule_folder_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
                title: Text(
                  decision.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  decision.summary.isNotEmpty
                      ? decision.summary
                      : '${decision.sourceType} • ${decision.createdByName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        sectionTitle(
          'KPI Decision Pack',
          subtitle: 'Usage sur les 14 derniers jours',
          trailing: TextButton.icon(
            onPressed: () => onRefreshDecisionPackAggregate(
              decisionPackAggregate?.sinceDays ?? 14,
            ),
            icon: const Icon(Icons.query_stats_rounded, size: 16),
            label: const Text('Actualiser'),
          ),
        ),
        if (loadingDecisionPackAggregate)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('7j'),
                  selected: (decisionPackAggregate?.sinceDays ?? 14) == 7,
                  onSelected: (_) => onRefreshDecisionPackAggregate(7),
                ),
                ChoiceChip(
                  label: const Text('14j'),
                  selected: (decisionPackAggregate?.sinceDays ?? 14) == 14,
                  onSelected: (_) => onRefreshDecisionPackAggregate(14),
                ),
                ChoiceChip(
                  label: const Text('30j'),
                  selected: (decisionPackAggregate?.sinceDays ?? 14) == 30,
                  onSelected: (_) => onRefreshDecisionPackAggregate(30),
                ),
                Chip(
                  avatar: const Icon(Icons.visibility_outlined, size: 16),
                  label: Text('Vues: ${decisionPackAggregate?.viewed ?? 0}'),
                ),
                Chip(
                  avatar: const Icon(Icons.share_outlined, size: 16),
                  label: Text('Partages: ${decisionPackAggregate?.shared ?? 0}'),
                ),
                Chip(
                  avatar: const Icon(Icons.error_outline, size: 16),
                  label: Text('Echecs: ${decisionPackAggregate?.shareFailed ?? 0}'),
                ),
                Builder(
                  builder: (_) {
                    final viewed = decisionPackAggregate?.viewed ?? 0;
                    final shared = decisionPackAggregate?.shared ?? 0;
                    final rate = viewed <= 0 ? 0 : ((shared / viewed) * 100).round();
                    return Chip(
                      avatar: const Icon(Icons.trending_up_rounded, size: 16),
                      label: Text('Conv.: $rate%'),
                    );
                  },
                ),
              ],
            ),
          ),
        sectionTitle(
          'Taches',
          subtitle: tasks.isEmpty ? 'Aucune tache suivie actuellement.' : null,
          trailing: TextButton.icon(
            onPressed: onOpenTaskBoard,
            icon: const Icon(Icons.view_kanban_outlined, size: 16),
            label: const Text('Board'),
          ),
        ),
        ...tasks.take(6).map(
              (task) => ListTile(
                dense: true,
                onTap: () => onEditTask(task),
                leading: Icon(
                  task.status == 'done'
                      ? Icons.check_circle_outline_rounded
                      : task.status == 'blocked'
                          ? Icons.block_outlined
                          : task.status == 'in_progress'
                              ? Icons.timelapse_rounded
                              : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: task.status == 'done'
                      ? Colors.green
                      : task.status == 'blocked'
                          ? scheme.error
                          : scheme.secondary,
                ),
                title: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    task.status,
                    if (task.ownerName.isNotEmpty) task.ownerName,
                    if (task.dueDate != null)
                      'echeance ${_dueLabel(task.dueDate)}',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
              ),
            ),
        sectionTitle(
          'Intégrations',
          subtitle:
              'Statut de connexion Slack/Notion et dernier état de synchronisation.',
        ),
        if (loadingIntegrations)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ...[
          ('Slack', slackIntegration, Icons.tag_rounded),
          ('Notion', notionIntegration, Icons.note_alt_outlined),
        ].map(
          (entry) {
            final label = entry.$1;
            final status = entry.$2;
            final icon = entry.$3;
            final connected = status?.connected == true;
            return ListTile(
              dense: true,
              leading: Icon(
                icon,
                color: connected ? Colors.green : scheme.onSurface,
                size: 18,
              ),
              title:
                  Text('$label · ${connected ? 'Connecte' : 'Non connecte'}'),
              subtitle: Text(
                _integrationSubtitle(label, status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                _integrationTrailingIcon(label, connected),
                size: 17,
                color: _integrationTrailingColor(label, connected, scheme),
              ),
            );
          },
        ),
        if (canManageIntegrations)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (slackIntegration?.connected == true)
                  OutlinedButton.icon(
                    onPressed: onDisconnectSlackIntegration,
                    icon: const Icon(Icons.link_off_rounded, size: 16),
                    label: const Text('Deconnecter Slack'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: onConnectSlackIntegration,
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Connecter Slack'),
                  ),
                if (notionIntegration?.connected == true)
                  OutlinedButton.icon(
                    onPressed: onDisconnectNotionIntegration,
                    icon: const Icon(Icons.link_off_rounded, size: 16),
                    label: const Text('Deconnecter Notion'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: onConnectNotionIntegration,
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Connecter Notion'),
                  ),
              ],
            ),
          ),
        if (!canManageIntegrations)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gestion des integrations reservee au proprietaire du channel.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: slackIntegration?.connected == true
                    ? onShareDecisionPackToSlack
                    : null,
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: const Text('Decision Pack → Slack'),
              ),
              FilledButton.icon(
                onPressed: notionIntegration?.connected == true
                    ? onShareDecisionPackToNotion
                    : null,
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: const Text('Decision Pack → Notion'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    slackIntegration?.connected == true ? onShareToSlack : null,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Partager vers Slack'),
              ),
              FilledButton.tonalIcon(
                onPressed: notionIntegration?.connected == true
                    ? onShareToNotion
                    : null,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Partager vers Notion'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRefreshIntegrations,
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: const Text('Actualiser'),
            ),
          ),
        ),
        sectionTitle(
          'Historique de partage',
          subtitle: shareHistory.isEmpty
              ? 'Aucun export vers Slack/Notion pour ce channel.'
              : null,
        ),
        if (loadingShareHistory)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (shareHistory.length > 4)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openShareHistorySheet(context, shareHistory),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: const Text('Voir tout'),
              ),
            ),
          ),
        ...shareHistory.take(4).map(
              (item) => ListTile(
                dense: true,
                leading: Icon(
                  item.target == 'slack'
                      ? Icons.tag_rounded
                      : Icons.note_alt_outlined,
                  size: 18,
                  color: item.isSuccess
                      ? Colors.green
                      : item.isFailed
                          ? scheme.error
                          : scheme.tertiary,
                ),
                title: Text(
                  '${item.target.toUpperCase()} · ${item.status}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.note.isNotEmpty
                      ? '${item.note} · ${_timeAgo(item.createdAt)}'
                      : '${item.summary.isEmpty ? 'Sans resume' : item.summary} · ${_timeAgo(item.createdAt)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: item.retries > 0
                    ? Chip(
                        label: Text('retry ${item.retries}'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )
                    : null,
              ),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRefreshShareHistory,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Rafraichir l\'historique'),
            ),
          ),
        ),
        sectionTitle('Actions rapides'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (useNeumorphControls) ...[
                NeumorphicActionButton(
                  icon: Icons.add_box_outlined,
                  label: 'Creer un canvas',
                  onPressed: () => onInsertCommand('/doc'),
                ),
                NeumorphicActionButton(
                  icon: Icons.travel_explore_rounded,
                  label: 'Attacher une recherche',
                  onPressed: () => onInsertCommand('/search'),
                ),
                NeumorphicActionButton(
                  icon: Icons.rule_folder_rounded,
                  label: 'Synthese de decision',
                  onPressed: () => onInsertCommand('/decide'),
                ),
                NeumorphicActionButton(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Lancer une mission IA',
                  onPressed: onLaunchMission,
                ),
              ] else ...[
                FilledButton.tonal(
                  onPressed: () => onInsertCommand('/doc'),
                  child: const Text('Creer un canvas'),
                ),
                FilledButton.tonal(
                  onPressed: () => onInsertCommand('/search'),
                  child: const Text('Attacher une recherche'),
                ),
                FilledButton.tonal(
                  onPressed: () => onInsertCommand('/decide'),
                  child: const Text('Synthese de decision'),
                ),
                FilledButton.tonal(
                  onPressed: onLaunchMission,
                  child: const Text('Lancer une mission IA'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openShareHistorySheet(
    BuildContext context,
    List<RoomShareHistoryItem> items,
  ) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Historique de partage',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${items.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      item.target == 'slack'
                          ? Icons.tag_rounded
                          : Icons.note_alt_outlined,
                      color: item.isSuccess ? Colors.green : scheme.tertiary,
                    ),
                    title: Text(
                      '${item.target.toUpperCase()} · ${item.status}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      item.errorMessage.isNotEmpty
                          ? item.errorMessage
                          : (item.note.isNotEmpty ? item.note : item.summary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _timeAgo(item.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openResearchHistorySheet(
    BuildContext context,
    List<RoomArtifact> researchArtifacts,
    void Function(RoomArtifact) onOpenCanvas,
  ) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Icon(Icons.travel_explore_rounded,
                      color: scheme.tertiary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Historique des recherches',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${researchArtifacts.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: researchArtifacts.length,
                itemBuilder: (ctx, i) {
                  final artifact = researchArtifacts[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.travel_explore_rounded,
                        color: scheme.tertiary),
                    title: Text(
                      artifact.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      artifact.currentVersion?.contentPreview ??
                          'research • ${artifact.status}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      onOpenCanvas(artifact);
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
                color: scheme.onSurface.withValues(alpha: 0.2),
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
                          : scheme.onSurface.withValues(alpha: 0.4),
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
                  color: scheme.onSurface.withValues(alpha: 0.2),
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
