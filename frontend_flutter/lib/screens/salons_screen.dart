import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/room.dart';
import '../providers/room_provider.dart';
import '../services/project_service.dart' show ProjectService;
import 'profile_screen.dart';
import 'salon_chat_screen.dart';

/// Lists the user's channels and allows creating new ones.
class SalonsScreen extends StatefulWidget {
  const SalonsScreen({super.key});

  @override
  State<SalonsScreen> createState() => _SalonsScreenState();
}

class _SalonsScreenState extends State<SalonsScreen> {
  bool _inviteHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<RoomProvider>();
      prov.loadRooms();
      prov.loadTemplateStats();
      _handleInviteLinkIfPresent(prov);
    });
  }

  Future<void> _handleInviteLinkIfPresent(RoomProvider prov) async {
    if (_inviteHandled || !mounted) return;

    final uri = Uri.base;
    final roomId = _extractInviteRoomId(uri);
    if (roomId == null || roomId.isEmpty) return;

    _inviteHandled = true;
    final room = await prov.joinRoomById(roomId);
    if (!mounted) return;

    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            prov.actionError ?? 'Impossible de rejoindre ce channel',
          ),
        ),
      );
      return;
    }

    _openRoom(context, room);
  }

  String? _extractInviteRoomId(Uri uri) {
    String normalize(String value) => value.startsWith('/') ? value : '/$value';

    final candidates = <String>[];
    if (uri.path.isNotEmpty) candidates.add(normalize(uri.path));
    if (uri.fragment.isNotEmpty) candidates.add(normalize(uri.fragment));

    for (final candidate in candidates) {
      final inviteMatch =
          RegExp(r'^/invite/([a-fA-F0-9]{24})').firstMatch(candidate);
      if (inviteMatch != null) return inviteMatch.group(1);

      final channelMatch =
          RegExp(r'^/channel/([a-fA-F0-9]{24})').firstMatch(candidate);
      if (channelMatch != null) return channelMatch.group(1);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prov = context.watch<RoomProvider>();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        title: const Text(
          'Channels',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Mon profil',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: () => prov.loadRooms(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero description
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Collaborez dans des channels partageables. L’IA est un collègue visible par tous quand vous l’interpellez avec @ia ou une commande.',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ),

          if (prov.loadingTemplateStats || prov.templateStats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _TemplateStatsCard(
                loading: prov.loadingTemplateStats,
                stats: prov.templateStats,
                onRefresh: () => prov.loadTemplateStats(force: true),
              ),
            ),

          // Body
          Expanded(
            child: prov.loadingRooms
                ? const Center(child: CircularProgressIndicator())
                : prov.roomsError != null
                    ? _ErrorState(
                        message: prov.roomsError!,
                        onRetry: prov.loadRooms,
                      )
                    : prov.rooms.isEmpty
                        ? _EmptyState(
                            onCreate: () => _showCreateDialog(context),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: prov.rooms.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (ctx, i) =>
                                _RoomTile(room: prov.rooms[i]),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create_salon',
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau channel'),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final prov = context.read<RoomProvider>();
    final nameCtrl = TextEditingController();

    // Kick off template loading (no-op if already cached)
    prov.loadTemplates();

    await showDialog<void>(
      context: context,
      builder: (ctx) => _CreateRoomDialog(
        nameCtrl: nameCtrl,
        prov: prov,
        onSubmit: (name, templateId) async {
          Navigator.of(ctx).pop();
          final displayName = _displayName();
          final room = await prov.createRoom(
            name: name,
            displayName: displayName,
            templateId: templateId,
          );
          if (room != null && context.mounted) {
            _openRoom(context, room);
          }
        },
      ),
    );
    nameCtrl.dispose();
  }

  void _openRoom(BuildContext context, Room room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalonChatScreen(room: room),
      ),
    );
  }

  String _displayName() {
    final uid = ProjectService.currentUserId ?? '';
    return ProjectService.currentDisplayName ??
        'User_${uid.isEmpty ? '????' : uid.substring(uid.length - 4)}';
  }
}

// ── Room tile ─────────────────────────────────────────────────────────────────

class _RoomTile extends StatelessWidget {
  final Room room;
  const _RoomTile({required this.room});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = room.name.isNotEmpty ? room.name[0].toUpperCase() : '?';

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SalonChatScreen(room: room),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(
                  initial,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          room.isDm
                              ? Icons.person_outline_rounded
                              : Icons.group_outlined,
                          size: 13,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${room.memberCount} membre${room.memberCount > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateStatsCard extends StatelessWidget {
  final bool loading;
  final List<DomainTemplateStats> stats;
  final VoidCallback onRefresh;

  const _TemplateStatsCard({
    required this.loading,
    required this.stats,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ranked = [...stats]
      ..sort((a, b) => b.feedbackAverage.compareTo(a.feedbackAverage));

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Performance des modèles IA',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser les stats',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: onRefresh,
                ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: LinearProgressIndicator(minHeight: 3),
              )
            else if (ranked.isEmpty)
              Text(
                'Aucune donnée template pour le moment.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            else
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ranked.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final s = ranked[i];
                    return Container(
                      width: 190,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.emoji} ${s.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${s.roomsCreated} rooms • ${s.messagesSent} msgs',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Score ${s.feedbackAverage.toStringAsFixed(2)} • D7 ${s.d7RetentionRate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
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
}

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 64, color: scheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'Pas encore de channel',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Créez un channel pour collaborer avec vos collègues.\nL’IA commune du channel vous aidera à produire, chercher et décider.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Créer un channel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create room dialog with template picker ───────────────────────────────────

class _CreateRoomDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final RoomProvider prov;
  final Future<void> Function(String name, String? templateId) onSubmit;

  const _CreateRoomDialog({
    required this.nameCtrl,
    required this.prov,
    required this.onSubmit,
  });

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  String? _selectedTemplateId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.prov,
      builder: (ctx, _) {
        final scheme = Theme.of(ctx).colorScheme;
        final templates = widget.prov.templates;
        final loading = widget.prov.loadingTemplates;

        return AlertDialog(
          title: const Text('Créer un channel'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Template picker ───────────────────────────────────────
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (templates.isNotEmpty) ...[
                  Text(
                    'Choisir un modèle (optionnel)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: templates.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final t = templates[i];
                        final selected = _selectedTemplateId == t.id;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTemplateId = selected ? null : t.id;
                              // Auto-fill name if still empty
                              if (!selected && widget.nameCtrl.text.isEmpty) {
                                widget.nameCtrl.text = t.name;
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 100,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                                width: selected ? 2 : 1,
                              ),
                              color: selected
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerLow,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(t.emoji,
                                    style: const TextStyle(fontSize: 24)),
                                const SizedBox(height: 4),
                                Text(
                                  t.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // ── Name field ────────────────────────────────────────────
                TextField(
                  controller: widget.nameCtrl,
                  autofocus: templates.isEmpty && !loading,
                  decoration: const InputDecoration(
                    labelText: 'Nom du channel',
                    hintText: 'Ex: IA produit',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 8),
                Text(
                  'Utilisez @ia, /doc, /search, /decide ou /mission une fois dedans.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final name = widget.nameCtrl.text.trim();
                if (name.isEmpty) return;
                await widget.onSubmit(name, _selectedTemplateId);
              },
              child: const Text('Créer'),
            ),
          ],
        );
      },
    );
  }
}
