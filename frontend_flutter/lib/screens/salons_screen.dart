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

  String _starterMissionPromptForTemplate(DomainTemplate? template) {
    final prompts = template?.starterPrompts ?? const <String>[];
    for (final prompt in prompts) {
      final trimmed = prompt.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Propose un plan d action priorise en 3 etapes pour lancer ce channel efficacement.';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<RoomProvider>();
      prov.loadRooms();
      prov.loadTemplates();
      prov.loadTemplateStats();
      _handleInviteLinkIfPresent(prov);
    });
  }

  String? _recommendedTemplateId(RoomProvider prov) {
    if (prov.templates.isEmpty) return null;
    final insights = prov.templateInsights;
    if (insights == null) return null;

    final available = prov.templates.map((t) => t.id).toSet();
    final underperforming = insights.underperformingTemplates
        .map((s) => s.templateId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final topFeedback = insights.topByFeedback?.templateId;
    if (topFeedback != null &&
        topFeedback.isNotEmpty &&
        available.contains(topFeedback) &&
        !underperforming.contains(topFeedback)) {
      return topFeedback;
    }

    final topD7 = insights.topByD7Retention?.templateId;
    if (topD7 != null &&
        topD7.isNotEmpty &&
        available.contains(topD7) &&
        !underperforming.contains(topD7)) {
      return topD7;
    }
    return null;
  }

  Future<void> _createRecommendedChannel(BuildContext context) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (prov.templates.isEmpty) {
      await prov.loadTemplates();
    }
    if (prov.templateStats.isEmpty) {
      await prov.loadTemplateStats(force: true);
    }

    final recommendedId = _recommendedTemplateId(prov);
    if (!context.mounted) return;
    if (recommendedId == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Pas encore assez de donnees: choisissez un modele manuellement.'),
        ),
      );
      _showCreateDialog(context);
      return;
    }

    DomainTemplate? template;
    for (final item in prov.templates) {
      if (item.id == recommendedId) {
        template = item;
        break;
      }
    }
    final baseName =
        template?.name.isNotEmpty == true ? template!.name : 'Channel IA';
    final generatedName =
        '$baseName ${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')}';

    final room = await prov.createRoom(
      name: generatedName,
      displayName: _displayName(),
      templateId: recommendedId,
      templateVersion: null,
    );
    if (!context.mounted) return;
    if (room == null) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Creation du channel recommande impossible.')),
      );
      return;
    }

    final missionPrompt = _starterMissionPromptForTemplate(template);
    bool missionSeeded = false;
    await prov.openRoom(room);
    if (context.mounted) {
      missionSeeded = await prov.createMission(missionPrompt);
    }
    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(missionSeeded
            ? 'Channel recommande cree avec ${template?.emoji ?? '🧠'} ${template?.name ?? 'modele IA'} + mission de demarrage.'
            : 'Channel recommande cree avec ${template?.emoji ?? '🧠'} ${template?.name ?? 'modele IA'}.'),
      ),
    );
    _openRoom(context, room);
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
    final recommendedTemplateId = _recommendedTemplateId(prov);
    DomainTemplate? recommendedTemplate;
    if (recommendedTemplateId != null) {
      for (final t in prov.templates) {
        if (t.id == recommendedTemplateId) {
          recommendedTemplate = t;
          break;
        }
      }
    }

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

          if (recommendedTemplate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: scheme.primary.withValues(alpha: 0.08),
                  border:
                      Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Text(recommendedTemplate.emoji,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Modele recommande: ${recommendedTemplate.name}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _createRecommendedChannel(context),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Creer channel recommande'),
                    ),
                  ],
                ),
              ),
            ),

          if (prov.loadingTemplateStats || prov.templateStats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _TemplateStatsCard(
                loading: prov.loadingTemplateStats,
                stats: prov.templateStats,
                insights: prov.templateInsights,
                sinceDays: prov.templateStatsSinceDays,
                groupBy: prov.templateStatsGroupBy,
                onRefresh: () => prov.loadTemplateStats(force: true),
                onSinceDaysChanged: (days) => prov.loadTemplateStats(
                  force: true,
                  sinceDays: days,
                ),
                onGroupByChanged: (groupBy) => prov.loadTemplateStats(
                  force: true,
                  groupBy: groupBy,
                ),
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
        onSubmit: (name, templateId, templateVersion) async {
          Navigator.of(ctx).pop();
          final displayName = _displayName();
          final room = await prov.createRoom(
            name: name,
            displayName: displayName,
            templateId: templateId,
            templateVersion: templateVersion,
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
  final DomainTemplateInsights? insights;
  final int sinceDays;
  final String groupBy;
  final VoidCallback onRefresh;
  final ValueChanged<int> onSinceDaysChanged;
  final ValueChanged<String> onGroupByChanged;

  const _TemplateStatsCard({
    required this.loading,
    required this.stats,
    required this.insights,
    required this.sinceDays,
    required this.groupBy,
    required this.onRefresh,
    required this.onSinceDaysChanged,
    required this.onGroupByChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ranked = [...stats]..sort((a, b) {
        if (a.isLowSample != b.isLowSample) {
          return a.isLowSample ? 1 : -1;
        }
        return b.feedbackAverage.compareTo(a.feedbackAverage);
      });

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
            Wrap(
              spacing: 6,
              children: [
                for (final d in const [7, 30, 90])
                  ChoiceChip(
                    label: Text('${d}j'),
                    selected: sinceDays == d,
                    onSelected: (_) => onSinceDaysChanged(d),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Template'),
                  selected: groupBy == 'template',
                  onSelected: (_) => onGroupByChanged('template'),
                ),
                ChoiceChip(
                  label: const Text('Version'),
                  selected: groupBy == 'version',
                  onSelected: (_) => onGroupByChanged('version'),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
                height: 112,
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
                      child: SingleChildScrollView(
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
                            if (groupBy == 'version' &&
                                s.templateVersion.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  s.templateVersion,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.55),
                                  ),
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
                            if (s.isLowSample)
                              Text(
                                'Faible echantillon',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else if (s.winner)
                              Text(
                                '🏆 Gagnant',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (!loading && insights != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Top score: ${insights!.topByFeedback?.emoji ?? ''} ${insights!.topByFeedback?.name ?? 'n/a'} • '
                  'Top D7: ${insights!.topByD7Retention?.emoji ?? ''} ${insights!.topByD7Retention?.name ?? 'n/a'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
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
  final Future<void> Function(
    String name,
    String? templateId,
    String? templateVersion,
  ) onSubmit;

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
  String? _selectedTemplateVersion;
  bool _forceNoTemplate = false;

  String? _recommendedTemplateId(List<DomainTemplate> templates) {
    if (templates.isEmpty) return null;
    final insights = widget.prov.templateInsights;
    if (insights == null) return null;

    final available = templates.map((t) => t.id).toSet();
    final blocked = insights.underperformingTemplates
        .map((s) => s.templateId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final feedback = insights.topByFeedback?.templateId;
    if (feedback != null &&
        feedback.isNotEmpty &&
        available.contains(feedback) &&
        !blocked.contains(feedback)) {
      return feedback;
    }

    final d7 = insights.topByD7Retention?.templateId;
    if (d7 != null &&
        d7.isNotEmpty &&
        available.contains(d7) &&
        !blocked.contains(d7)) {
      return d7;
    }
    return null;
  }

  DomainTemplateStats? _statsForTemplate(String templateId) {
    if (templateId.isEmpty) return null;
    final matching = widget.prov.templateStats
        .where((s) => s.templateId == templateId)
        .toList();
    if (matching.isEmpty) return null;
    matching.sort((a, b) {
      if (a.isLowSample != b.isLowSample) {
        return a.isLowSample ? 1 : -1;
      }
      if (b.roomsCreated != a.roomsCreated) {
        return b.roomsCreated.compareTo(a.roomsCreated);
      }
      return b.d7RetentionRate.compareTo(a.d7RetentionRate);
    });
    return matching.first;
  }

  String? _reasonForTemplate(String templateId) {
    if (templateId.isEmpty) return null;
    final insights = widget.prov.templateInsights;
    if (insights == null) return null;
    if (insights.topByFeedback?.templateId == templateId) {
      return 'Top feedback';
    }
    if (insights.topByD7Retention?.templateId == templateId) {
      return 'Top retention D7';
    }
    if (insights.underperformingTemplates
        .any((s) => s.templateId == templateId)) {
      return 'Sous performance';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.prov,
      builder: (ctx, _) {
        final scheme = Theme.of(ctx).colorScheme;
        final templates = [...widget.prov.templates];
        final loading = widget.prov.loadingTemplates;
        final recommendedTemplateId = _recommendedTemplateId(templates);

        templates.sort((a, b) {
          final aRecommended = a.id == recommendedTemplateId;
          final bRecommended = b.id == recommendedTemplateId;
          if (aRecommended != bRecommended) return aRecommended ? -1 : 1;

          final aReason = _reasonForTemplate(a.id);
          final bReason = _reasonForTemplate(b.id);
          const priority = {
            'Top feedback': 0,
            'Top retention D7': 1,
            'Sous performance': 3,
          };
          final aRank = priority[aReason] ?? 2;
          final bRank = priority[bReason] ?? 2;
          if (aRank != bRank) return aRank.compareTo(bRank);
          return a.name.compareTo(b.name);
        });

        final effectiveTemplateId = _forceNoTemplate
            ? null
            : (_selectedTemplateId ?? recommendedTemplateId);
        DomainTemplate? selectedTemplate;
        for (final t in templates) {
          if (t.id == effectiveTemplateId) {
            selectedTemplate = t;
            break;
          }
        }
        final selectedTemplateName = selectedTemplate?.name ?? '';

        final selectedStats = selectedTemplate == null
            ? null
            : _statsForTemplate(selectedTemplate.id);
        final selectedReason = selectedTemplate == null
            ? null
            : _reasonForTemplate(selectedTemplate.id);

        final selectedWeights = (selectedTemplate?.versionWeights.entries
                .where((e) => e.value > 0)
                .toList() ??
            <MapEntry<String, int>>[]);
        selectedWeights.sort((a, b) => a.key.compareTo(b.key));
        final rolloutText =
            selectedWeights.map((e) => '${e.key} ${e.value}%').join(' / ');
        final availableVersions = selectedWeights
            .map((e) => e.key)
            .where((v) => v.isNotEmpty)
            .toList();
        if (availableVersions.isEmpty &&
            selectedTemplate != null &&
            selectedTemplate.version.isNotEmpty) {
          availableVersions.add(selectedTemplate.version);
        }
        final hasMultiVersion = availableVersions.length > 1;
        if (_selectedTemplateVersion != null &&
            !availableVersions.contains(_selectedTemplateVersion)) {
          _selectedTemplateVersion = null;
        }

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
                  if (recommendedTemplateId != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: scheme.primary.withValues(alpha: 0.1),
                      ),
                      child: Text(
                        'Recommandation auto activee: meilleur modele selon feedback et retention.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: templates.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                          final selected = effectiveTemplateId == null;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedTemplateId = null;
                                _selectedTemplateVersion = null;
                                _forceNoTemplate = true;
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
                                  Icon(
                                    Icons.block_rounded,
                                    size: 24,
                                    color: selected
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Aucun modèle',
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
                        }

                        final t = templates[i - 1];
                        final selected = effectiveTemplateId == t.id;
                        final reason = _reasonForTemplate(t.id);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTemplateId = selected ? null : t.id;
                              _forceNoTemplate = selected;
                              if (selected) {
                                _selectedTemplateVersion = null;
                              }
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
                                  t.version.isEmpty
                                      ? t.name
                                      : '${t.name} ${t.version}',
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
                                if (reason != null &&
                                    reason != 'Sous performance')
                                  Text(
                                    reason == 'Top feedback'
                                        ? 'Top 👍'
                                        : 'Top D7',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? scheme.onPrimaryContainer
                                          : scheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: scheme.surfaceContainerHigh,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: selectedTemplate == null
                        ? Text(
                            'Sans modèle: le channel sera créé sans directives IA prédéfinies.',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${selectedTemplate.emoji} ${selectedTemplate.name}${selectedTemplate.version.isEmpty ? '' : ' ${selectedTemplate.version}'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                selectedTemplate.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'But: ${selectedTemplate.purpose}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                              if (selectedReason != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: selectedReason == 'Sous performance'
                                        ? scheme.error.withValues(alpha: 0.1)
                                        : scheme.primary.withValues(alpha: 0.1),
                                  ),
                                  child: Text(
                                    selectedReason == 'Sous performance'
                                        ? 'Attention: ce modele est actuellement sous la moyenne.'
                                        : 'Pourquoi recommande: $selectedReason',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          selectedReason == 'Sous performance'
                                              ? scheme.error
                                              : scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                              if (selectedStats != null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _MetricChip(
                                      label: 'Feedback',
                                      value:
                                          '${selectedStats.feedbackAverage >= 0 ? '+' : ''}${selectedStats.feedbackAverage.toStringAsFixed(2)}',
                                    ),
                                    _MetricChip(
                                      label: 'Retention D7',
                                      value:
                                          '${selectedStats.d7RetentionRate.toStringAsFixed(1)}%',
                                    ),
                                    _MetricChip(
                                      label: 'Rooms',
                                      value: '${selectedStats.roomsCreated}',
                                    ),
                                  ],
                                ),
                              ],
                              if (selectedTemplate
                                  .starterPrompts.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Prompts de depart',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final prompt in selectedTemplate
                                        .starterPrompts
                                        .take(3))
                                      ActionChip(
                                        label: Text(
                                          prompt,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onPressed: () {
                                          widget.nameCtrl.text =
                                              selectedTemplateName;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Prompt pret: "$prompt"',
                                              ),
                                              duration:
                                                  const Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ],
                              if (hasMultiVersion) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Version (optionnel)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Auto (rollout)'),
                                      selected:
                                          _selectedTemplateVersion == null,
                                      onSelected: (_) {
                                        setState(() {
                                          _selectedTemplateVersion = null;
                                        });
                                      },
                                    ),
                                    for (final version in availableVersions)
                                      ChoiceChip(
                                        label: Text(version),
                                        selected:
                                            _selectedTemplateVersion == version,
                                        onSelected: (_) {
                                          setState(() {
                                            _selectedTemplateVersion = version;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ],
                              if (rolloutText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Rollout: $rolloutText',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                              if (hasMultiVersion &&
                                  _selectedTemplateVersion == null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color:
                                        scheme.primary.withValues(alpha: 0.1),
                                  ),
                                  child: Text(
                                    'ℹ️ La version sera assignée automatiquement selon le rollout configuré (ex: $rolloutText)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                await widget.onSubmit(
                  name,
                  effectiveTemplateId,
                  _selectedTemplateVersion,
                );
              },
              child: const Text('Créer'),
            ),
          ],
        );
      },
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          color: scheme.onSurface.withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
