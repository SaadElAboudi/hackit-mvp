import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import '../models/room.dart';
import '../providers/room_provider.dart';

/// Board d'execution: vue Kanban des taches et decisions.
class ExecutionBoardScreen extends StatefulWidget {
  const ExecutionBoardScreen({super.key});

  @override
  State<ExecutionBoardScreen> createState() => _ExecutionBoardScreenState();
}

class _ExecutionBoardScreenState extends State<ExecutionBoardScreen> {
  Map<String, List<WorkspaceTask>> _tasksByStatus = {};
  Map<String, List<WorkspaceDecision>> _decisionsByStatus = {};
  int _activeBoardIndex = 0;
  bool _switchingRoom = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = context.read<RoomProvider>();
      await prov.ensureCurrentRoom(createIfMissing: false);
      if (!mounted) return;
      setState(() {
        _rebuildMaps();
      });
    });
  }

  void _rebuildMaps() {
    final prov = context.read<RoomProvider>();
    _tasksByStatus = {
      'todo': prov.tasks.where((t) => t.status == 'todo').toList(),
      'in_progress':
          prov.tasks.where((t) => t.status == 'in_progress').toList(),
      'blocked': prov.tasks.where((t) => t.status == 'blocked').toList(),
      'done': prov.tasks.where((t) => t.status == 'done').toList(),
    };
    _decisionsByStatus = {
      'draft': prov.decisions.where((d) => d.status == 'draft').toList(),
      'review': prov.decisions.where((d) => d.status == 'review').toList(),
      'approved': prov.decisions.where((d) => d.status == 'approved').toList(),
      'implemented':
          prov.decisions.where((d) => d.status == 'implemented').toList(),
    };
  }

  Future<void> _openRoom(Room room) async {
    try {
      setState(() => _switchingRoom = true);
      final prov = context.read<RoomProvider>();
      await prov.openRoom(room);
      if (!mounted) return;
      setState(() {
        _rebuildMaps();
        _switchingRoom = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _switchingRoom = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d ouvrir le salon: $e')),
      );
    }
  }

  Future<void> _createGeneralRoom() async {
    try {
      final prov = context.read<RoomProvider>();
      final room = await prov.createRoom(
        name: 'General',
        displayName: prov.myUserId ?? 'Utilisateur',
      );
      if (room == null) return;
      await _openRoom(room);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Creation du salon impossible: $e')),
      );
    }
  }

  @override
  void didUpdateWidget(ExecutionBoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildMaps();
  }

  Future<void> _handleStatusChange(
    WorkspaceTask task,
    String newStatus,
  ) async {
    try {
      final prov = context.read<RoomProvider>();
      await prov.updateTask(task, status: newStatus);
      if (!mounted) return;
      setState(() {
        _rebuildMaps();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Echec du changement de statut: $e')),
      );
    }
  }

  Future<void> _handleDecisionStatusChange(
    WorkspaceDecision decision,
    String newStatus,
  ) async {
    try {
      final prov = context.read<RoomProvider>();
      await prov.updateDecision(decision, status: newStatus);
      if (!mounted) return;
      setState(() {
        _rebuildMaps();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Echec du changement de statut: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoomProvider>();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    _rebuildMaps();

    if (prov.currentRoom == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Execution board')),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primary.withValues(alpha: 0.08),
                scheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selectionne un salon pour afficher le Kanban.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          prov.loadingRooms ? null : () => prov.loadRooms(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Actualiser'),
                    ),
                    FilledButton.icon(
                      onPressed: _createGeneralRoom,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Creer General'),
                    ),
                  ],
                ),
                if (prov.roomsError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    prov.roomsError!,
                    style: text.bodySmall?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 14),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: prov.loadingRooms
                        ? const Center(
                            key: ValueKey('rooms_loading'),
                            child: CircularProgressIndicator(),
                          )
                        : prov.rooms.isEmpty
                            ? Center(
                                key: const ValueKey('rooms_empty'),
                                child: Text(
                                  'Aucun salon disponible.',
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.58),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                key: const ValueKey('rooms_list'),
                                itemCount: prov.rooms.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final room = prov.rooms[index];
                                  return Material(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => _openRoom(room),
                                      child: Ink(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: scheme.outlineVariant
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: scheme.primary
                                                  .withValues(alpha: 0.15),
                                              foregroundColor: scheme.primary,
                                              child: const Icon(
                                                  Icons.forum_rounded),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    room.name,
                                                    style: text.titleMedium
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${room.memberCount} membre(s)',
                                                    style: text.bodySmall
                                                        ?.copyWith(
                                                      color: scheme.onSurface
                                                          .withValues(
                                                              alpha: 0.65),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                                Icons.chevron_right_rounded),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalTasks = prov.tasks.length;
    final totalDecisions = prov.decisions.length;
    final blockedTasks = _tasksByStatus['blocked']?.length ?? 0;
    final doneTasks = _tasksByStatus['done']?.length ?? 0;
    final completionRate =
        totalTasks == 0 ? 0 : ((doneTasks / totalTasks) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Execution board'),
        actions: [
          if (_switchingRoom)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(alpha: 0.06),
              scheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            _BoardHero(
              roomName: prov.currentRoom?.name ?? 'Salon actif',
              totalTasks: totalTasks,
              blockedTasks: blockedTasks,
              totalDecisions: totalDecisions,
              completionRate: completionRate,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.task_alt_rounded),
                    label: Text('Taches'),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.rule_folder_outlined),
                    label: Text('Decisions'),
                  ),
                ],
                selected: {_activeBoardIndex},
                onSelectionChanged: (selection) {
                  setState(() {
                    _activeBoardIndex = selection.first;
                  });
                },
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _activeBoardIndex == 0
                    ? _TasksBoard(
                        key: const ValueKey('tasks_board'),
                        tasksByStatus: _tasksByStatus,
                        onStatusChange: _handleStatusChange,
                      )
                    : _DecisionsBoard(
                        key: const ValueKey('decisions_board'),
                        decisionsByStatus: _decisionsByStatus,
                        onStatusChange: _handleDecisionStatusChange,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardHero extends StatelessWidget {
  final String roomName;
  final int totalTasks;
  final int blockedTasks;
  final int totalDecisions;
  final int completionRate;

  const _BoardHero({
    required this.roomName,
    required this.totalTasks,
    required this.blockedTasks,
    required this.totalDecisions,
    required this.completionRate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.16),
            scheme.tertiary.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roomName,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Pilotage en temps reel des taches et decisions',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroMetric(label: 'Taches', value: '$totalTasks'),
              _HeroMetric(label: 'Bloquees', value: '$blockedTasks'),
              _HeroMetric(label: 'Decisions', value: '$totalDecisions'),
              _HeroMetric(label: 'Done', value: '$completionRate%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksBoard extends StatelessWidget {
  final Map<String, List<WorkspaceTask>> tasksByStatus;
  final Future<void> Function(WorkspaceTask, String) onStatusChange;

  const _TasksBoard({
    super.key,
    required this.tasksByStatus,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const columns = ['todo', 'in_progress', 'blocked', 'done'];

    return _HorizontalWheelScroll(
      child: SizedBox(
        width: columns.length * 336.0,
        child: Row(
          children: columns.map((status) {
            final tasks = tasksByStatus[status] ?? [];
            return _KanbanColumn<WorkspaceTask>(
              title: _formatTaskStatus(status),
              count: tasks.length,
              items: tasks,
              statusOptions: const [
                'todo',
                'in_progress',
                'blocked',
                'done',
              ],
              currentStatus: status,
              onStatusChange: onStatusChange,
              columnColor: _statusColor(status, scheme),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DecisionsBoard extends StatelessWidget {
  final Map<String, List<WorkspaceDecision>> decisionsByStatus;
  final Future<void> Function(WorkspaceDecision, String) onStatusChange;

  const _DecisionsBoard({
    super.key,
    required this.decisionsByStatus,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const columns = ['draft', 'review', 'approved', 'implemented'];

    return _HorizontalWheelScroll(
      child: SizedBox(
        width: columns.length * 336.0,
        child: Row(
          children: columns.map((status) {
            final decisions = decisionsByStatus[status] ?? [];
            return _KanbanColumn<WorkspaceDecision>(
              title: _formatDecisionStatus(status),
              count: decisions.length,
              items: decisions,
              statusOptions: const [
                'draft',
                'review',
                'approved',
                'implemented',
              ],
              currentStatus: status,
              onStatusChange: onStatusChange,
              columnColor: _statusColor(status, scheme),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _HorizontalWheelScroll extends StatefulWidget {
  final Widget child;

  const _HorizontalWheelScroll({required this.child});

  @override
  State<_HorizontalWheelScroll> createState() => _HorizontalWheelScrollState();
}

class _HorizontalWheelScrollState extends State<_HorizontalWheelScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;

    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final horizontalDelta = dx.abs() > dy.abs() ? dx : dy;
    if (horizontalDelta == 0) return;

    final position = _controller.position;
    final nextOffset = (position.pixels + horizontalDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (nextOffset != position.pixels) {
      _controller.animateTo(
        nextOffset,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: widget.child,
        ),
      ),
    );
  }
}

class _KanbanColumn<T> extends StatelessWidget {
  final String title;
  final int count;
  final List<T> items;
  final List<String> statusOptions;
  final String currentStatus;
  final Future<void> Function(T, String) onStatusChange;
  final Color columnColor;

  const _KanbanColumn({
    required this.title,
    required this.count,
    required this.items,
    required this.statusOptions,
    required this.currentStatus,
    required this.onStatusChange,
    required this.columnColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 324,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: columnColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: columnColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(color: columnColor.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: columnColor,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: columnColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: columnColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          color: scheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Aucun element',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    itemBuilder: (ctx, idx) {
                      final item = items[idx];
                      return _KanbanCard<T>(
                        item: item,
                        statusOptions: statusOptions,
                        currentStatus: currentStatus,
                        onStatusChange: onStatusChange,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _KanbanCard<T> extends StatelessWidget {
  final T item;
  final List<String> statusOptions;
  final String currentStatus;
  final Future<void> Function(T, String) onStatusChange;

  const _KanbanCard({
    required this.item,
    required this.statusOptions,
    required this.currentStatus,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTask = item is WorkspaceTask;
    final title = isTask
        ? (item as WorkspaceTask).title
        : (item as WorkspaceDecision).title;
    final ownerName = isTask
        ? (item as WorkspaceTask).ownerName
        : (item as WorkspaceDecision).ownerName;
    final dueDate = isTask
        ? (item as WorkspaceTask).dueDate
        : (item as WorkspaceDecision).dueDate;
    final dueNow = dueDate != null && dueDate.isBefore(DateTime.now());
    final statusFormatter = isTask ? _formatTaskStatus : _formatDecisionStatus;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _showCardMenu(context, scheme);
          },
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.16),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface,
                  scheme.surfaceContainerLowest,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ownerName.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 14,
                        color: scheme.onSurface.withValues(alpha: 0.52),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ownerName,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.64),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (dueDate != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (dueNow ? scheme.error : scheme.tertiary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatDate(dueDate),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: dueNow ? scheme.error : scheme.tertiary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _StatusChangeMenu(
                  statusOptions: statusOptions,
                  currentStatus: currentStatus,
                  formatStatus: statusFormatter,
                  onStatusChange: (newStatus) {
                    onStatusChange(item, newStatus);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCardMenu(BuildContext context, ColorScheme scheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Actions carte: modifier, supprimer (bientot)'),
        duration: Duration(milliseconds: 2000),
      ),
    );
  }
}

class _StatusChangeMenu extends StatelessWidget {
  final List<String> statusOptions;
  final String currentStatus;
  final String Function(String) formatStatus;
  final Function(String) onStatusChange;

  const _StatusChangeMenu({
    required this.statusOptions,
    required this.currentStatus,
    required this.formatStatus,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onStatusChange,
      itemBuilder: (ctx) => statusOptions
          .map(
            (status) => PopupMenuItem(
              value: status,
              child: Row(
                children: [
                  if (status == currentStatus)
                    const Icon(Icons.check_rounded, size: 16)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(formatStatus(status)),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz_rounded, size: 14),
            const SizedBox(width: 4),
            Text(
              formatStatus(currentStatus),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTaskStatus(String status) {
  switch (status) {
    case 'todo':
      return 'A faire';
    case 'in_progress':
      return 'En cours';
    case 'blocked':
      return 'Bloque';
    case 'done':
      return 'Termine';
    default:
      return status;
  }
}

String _formatDecisionStatus(String status) {
  switch (status) {
    case 'draft':
      return 'Brouillon';
    case 'review':
      return 'En revue';
    case 'approved':
      return 'Approuve';
    case 'implemented':
      return 'Implemente';
    default:
      return status;
  }
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final dayDiff = target.difference(today).inDays;

  if (dayDiff == 0) {
    return 'Aujourd hui';
  } else if (dayDiff == 1) {
    return 'Demain';
  } else if (dayDiff > 1 && dayDiff < 7) {
    return 'Dans ${dayDiff}j';
  } else if (dayDiff < 0 && dayDiff > -7) {
    return 'Il y a ${-dayDiff}j';
  } else {
    return '${date.day}/${date.month}';
  }
}

Color _statusColor(String status, ColorScheme scheme) {
  switch (status) {
    case 'done':
    case 'implemented':
      return const Color(0xFF2E8B57);
    case 'blocked':
      return scheme.error;
    case 'review':
    case 'in_progress':
      return scheme.tertiary;
    default:
      return scheme.primary;
  }
}
