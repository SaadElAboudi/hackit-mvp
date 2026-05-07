import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';
import 'execution_board_screen.dart';
import 'inbox_screen.dart';
import 'ops_hub_screen.dart';

class HomeOverviewScreen extends StatefulWidget {
  final VoidCallback onOpenPriorities;
  final VoidCallback onOpenSalons;

  const HomeOverviewScreen({
    super.key,
    required this.onOpenPriorities,
    required this.onOpenSalons,
  });

  @override
  State<HomeOverviewScreen> createState() => _HomeOverviewScreenState();
}

class _HomeOverviewScreenState extends State<HomeOverviewScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final prov = context.read<RoomProvider>();
    await prov.loadRooms();
    final hasRoom = await prov.ensureCurrentRoom(createIfMissing: true);
    if (!hasRoom || !mounted) return;
    await Future.wait([
      prov.refreshExecutionPulse(silent: true),
      prov.loadFeedbackDigest(silent: true),
    ]);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final prov = context.read<RoomProvider>();
      await prov.loadRooms(force: true);
      final hasRoom = await prov.ensureCurrentRoom(createIfMissing: true);
      if (!hasRoom) return;
      await Future.wait([
        prov.refreshExecutionPulse(silent: true),
        prov.loadFeedbackDigest(silent: true),
      ]);
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoomProvider>();
    final scheme = Theme.of(context).colorScheme;
    final tasks = prov.tasks;
    final blocked = tasks.where((task) => task.status == 'blocked').length;
    final done = tasks.where((task) => task.status == 'done').length;
    final unassigned = tasks
        .where((task) =>
            task.ownerId.trim().isEmpty && task.ownerName.trim().isEmpty)
        .length;
    final roomName = prov.currentRoom?.name ?? 'Aucun salon actif';
    final pulse = prov.executionPulse;
    final scoreLabel = pulse != null ? '${pulse.score}/100' : 'En chargement';
    final statusLabel =
        pulse != null ? _pulseLabel(pulse.status) : 'Initialisation';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accueil'),
        elevation: 0,
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _refreshing ? null : _refresh,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.14),
                    scheme.tertiary.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: scheme.primary.withValues(alpha: 0.16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Passez de la discussion a l execution.',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Retrouvez vos priorites, ouvrez le board et remettez-vous dans le bon salon sans chercher dans cinq onglets.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: widget.onOpenPriorities,
                        icon: const Icon(
                            Icons.playlist_add_check_circle_outlined),
                        label: const Text('Voir mes priorites'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onOpenSalons,
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Changer de salon'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: scheme.outline.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.radio_button_checked,
                            color: scheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Salon actif',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              roomName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$statusLabel · $scoreLabel',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetricPill(
                          label: 'Bloquees',
                          value: '$blocked',
                          tone: scheme.error),
                      _MetricPill(
                          label: 'Terminees',
                          value: '$done',
                          tone: const Color(0xFF2E8B57)),
                      _MetricPill(
                          label: 'Sans owner',
                          value: '$unassigned',
                          tone: scheme.tertiary),
                      _MetricPill(
                          label: 'Decisions',
                          value: '${prov.decisions.length}',
                          tone: scheme.primary),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Acces direct',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            _ShortcutTile(
              icon: Icons.inbox_outlined,
              title: 'Vider ma file d attente',
              subtitle:
                  'Traiter les elements a convertir en action ou a snoozer.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InboxScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _ShortcutTile(
              icon: Icons.dashboard_customize_outlined,
              title: 'Ouvrir le board d execution',
              subtitle: 'Piloter les taches et decisions dans une vue claire.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ExecutionBoardScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _ShortcutTile(
              icon: Icons.monitor_heart_outlined,
              title: 'Voir le pilotage detaille',
              subtitle:
                  'Consulter le pulse, les feedbacks et les exports recents.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OpsHubScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _pulseLabel(String status) {
    switch (status) {
      case 'critical':
        return 'Critique';
      case 'attention':
        return 'Attention';
      default:
        return 'Sous controle';
    }
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color tone;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$value ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
