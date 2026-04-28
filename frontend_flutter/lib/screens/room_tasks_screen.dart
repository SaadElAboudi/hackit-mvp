import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/room.dart';
import '../providers/room_provider.dart';

class RoomTasksScreen extends StatefulWidget {
  final String roomName;
  final Future<void> Function(WorkspaceTask task) onEditTask;

  const RoomTasksScreen({
    super.key,
    required this.roomName,
    required this.onEditTask,
  });

  @override
  State<RoomTasksScreen> createState() => _RoomTasksScreenState();
}

class _RoomTasksScreenState extends State<RoomTasksScreen> {
  final _queryCtrl = TextEditingController();
  final Set<String> _updatingTaskIds = <String>{};
  bool _hideDone = false;
  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  List<WorkspaceTask> _applyFilters(List<WorkspaceTask> tasks) {
    final normalizedQuery = _query.trim().toLowerCase();
    return tasks.where((task) {
      if (_hideDone && task.status == 'done') return false;
      if (normalizedQuery.isEmpty) return true;
      final haystack = [
        task.title,
        task.description,
        task.ownerName,
      ].join(' ').toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();
  }

  Future<void> _moveTask(WorkspaceTask task, String status) async {
    if (_updatingTaskIds.contains(task.id) || task.status == status) return;
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _updatingTaskIds.add(task.id));
    final updated = await prov.updateTask(task, status: status);
    if (!mounted) return;
    setState(() => _updatingTaskIds.remove(task.id));

    if (updated == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            prov.actionError ?? 'Impossible de mettre a jour la tache',
          ),
        ),
      );
    }
  }

  int _countByStatus(List<WorkspaceTask> tasks, String status) {
    return tasks.where((task) => task.status == status).length;
  }

  int _dueSoonCount(List<WorkspaceTask> tasks) {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 3));
    return tasks.where((task) {
      if (task.status == 'done' || task.dueDate == null) return false;
      return !task.dueDate!.isBefore(now) && !task.dueDate!.isAfter(horizon);
    }).length;
  }

  int _overdueCount(List<WorkspaceTask> tasks) {
    final now = DateTime.now();
    return tasks.where((task) {
      if (task.status == 'done' || task.dueDate == null) return false;
      return task.dueDate!.isBefore(now);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prov = context.watch<RoomProvider>();
    final allTasks = prov.tasks.toList()
      ..sort((left, right) => _compareTasks(left, right));
    final filteredTasks = _applyFilters(allTasks);
    final columns = <_TaskColumnConfig>[
      _TaskColumnConfig(
        status: 'todo',
        title: 'A faire',
        emptyLabel: 'Rien a preparer pour le moment.',
        icon: Icons.radio_button_unchecked_rounded,
        color: scheme.primary,
      ),
      _TaskColumnConfig(
        status: 'in_progress',
        title: 'En cours',
        emptyLabel: 'Aucune tache active.',
        icon: Icons.timelapse_rounded,
        color: scheme.tertiary,
      ),
      _TaskColumnConfig(
        status: 'blocked',
        title: 'Bloquees',
        emptyLabel: 'Aucun blocage signale.',
        icon: Icons.block_outlined,
        color: scheme.error,
      ),
      const _TaskColumnConfig(
        status: 'done',
        title: 'Terminees',
        emptyLabel: 'Aucune tache terminee.',
        icon: Icons.check_circle_outline_rounded,
        color: Color(0xFF2E8B57),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Board taches · ${widget.roomName}'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1160;
          final board = filteredTasks.isEmpty
              ? _EmptyTaskBoard(
                  hasTasks: allTasks.isNotEmpty,
                  query: _query,
                  hideDone: _hideDone,
                )
              : isWide
                  ? _WideTaskBoard(
                      columns: columns,
                      tasks: filteredTasks,
                      updatingTaskIds: _updatingTaskIds,
                      onEditTask: widget.onEditTask,
                      onMoveTask: _moveTask,
                    )
                  : _StackedTaskBoard(
                      columns: columns,
                      tasks: filteredTasks,
                      updatingTaskIds: _updatingTaskIds,
                      onEditTask: widget.onEditTask,
                      onMoveTask: _moveTask,
                    );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _TaskMetricCard(
                          label: 'Total',
                          value: '${allTasks.length}',
                          icon: Icons.fact_check_outlined,
                          color: scheme.primary,
                        ),
                        _TaskMetricCard(
                          label: 'En cours',
                          value: '${_countByStatus(allTasks, 'in_progress')}',
                          icon: Icons.timelapse_rounded,
                          color: scheme.tertiary,
                        ),
                        _TaskMetricCard(
                          label: 'Bloquees',
                          value: '${_countByStatus(allTasks, 'blocked')}',
                          icon: Icons.block_outlined,
                          color: scheme.error,
                        ),
                        _TaskMetricCard(
                          label: 'Urgentes',
                          value:
                              '${_overdueCount(allTasks) + _dueSoonCount(allTasks)}',
                          icon: Icons.event_busy_outlined,
                          color: scheme.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _queryCtrl,
                            decoration: InputDecoration(
                              hintText:
                                  'Filtrer par titre, description ou responsable',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        _queryCtrl.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                      tooltip: 'Effacer le filtre',
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilterChip(
                          selected: _hideDone,
                          label: const Text('Masquer terminees'),
                          onSelected: (value) =>
                              setState(() => _hideDone = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(child: board),
            ],
          );
        },
      ),
    );
  }
}

class _WideTaskBoard extends StatelessWidget {
  final List<_TaskColumnConfig> columns;
  final List<WorkspaceTask> tasks;
  final Set<String> updatingTaskIds;
  final Future<void> Function(WorkspaceTask task) onEditTask;
  final Future<void> Function(WorkspaceTask task, String status) onMoveTask;

  const _WideTaskBoard({
    required this.columns,
    required this.tasks,
    required this.updatingTaskIds,
    required this.onEditTask,
    required this.onMoveTask,
  });

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: columns.map((column) {
            final columnTasks =
                tasks.where((task) => task.status == column.status).toList();
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 320,
                child: _TaskBoardColumn(
                  column: column,
                  tasks: columnTasks,
                  updatingTaskIds: updatingTaskIds,
                  onEditTask: onEditTask,
                  onMoveTask: onMoveTask,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _StackedTaskBoard extends StatelessWidget {
  final List<_TaskColumnConfig> columns;
  final List<WorkspaceTask> tasks;
  final Set<String> updatingTaskIds;
  final Future<void> Function(WorkspaceTask task) onEditTask;
  final Future<void> Function(WorkspaceTask task, String status) onMoveTask;

  const _StackedTaskBoard({
    required this.columns,
    required this.tasks,
    required this.updatingTaskIds,
    required this.onEditTask,
    required this.onMoveTask,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: columns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final column = columns[index];
        final columnTasks =
            tasks.where((task) => task.status == column.status).toList();
        return _TaskBoardColumn(
          column: column,
          tasks: columnTasks,
          updatingTaskIds: updatingTaskIds,
          onEditTask: onEditTask,
          onMoveTask: onMoveTask,
        );
      },
    );
  }
}

class _TaskBoardColumn extends StatelessWidget {
  final _TaskColumnConfig column;
  final List<WorkspaceTask> tasks;
  final Set<String> updatingTaskIds;
  final Future<void> Function(WorkspaceTask task) onEditTask;
  final Future<void> Function(WorkspaceTask task, String status) onMoveTask;

  const _TaskBoardColumn({
    required this.column,
    required this.tasks,
    required this.updatingTaskIds,
    required this.onEditTask,
    required this.onMoveTask,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: column.color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: column.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(column.icon, color: column.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    column.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text('${tasks.length}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  column.emptyLabel,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              )
            else
              ...tasks.map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TaskCard(
                    task: task,
                    busy: updatingTaskIds.contains(task.id),
                    onEdit: () => onEditTask(task),
                    onMoveTask: (status) => onMoveTask(task, status),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final WorkspaceTask task;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<String> onMoveTask;

  const _TaskCard({
    required this.task,
    required this.busy,
    required this.onEdit,
    required this.onMoveTask,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dueDate = task.dueDate;
    final isOverdue = dueDate != null &&
        dueDate.isBefore(DateTime.now()) &&
        task.status != 'done';

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : PopupMenuButton<String>(
                          tooltip: 'Changer le statut',
                          onSelected: onMoveTask,
                          itemBuilder: (_) => _taskStatusOptions
                              .where((option) => option.status != task.status)
                              .map(
                                (option) => PopupMenuItem<String>(
                                  value: option.status,
                                  child: Row(
                                    children: [
                                      Icon(option.icon, size: 16),
                                      const SizedBox(width: 8),
                                      Text(option.label),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          child: const Icon(Icons.more_horiz_rounded),
                        ),
                ],
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  task.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TaskMetaChip(
                    icon: Icons.person_outline_rounded,
                    label: task.ownerName.isEmpty
                        ? 'Non assignee'
                        : task.ownerName,
                  ),
                  if (dueDate != null)
                    _TaskMetaChip(
                      icon: isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.event_outlined,
                      label: _formatDate(dueDate),
                      color: isOverdue ? scheme.error : scheme.secondary,
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

class _TaskMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _TaskMetaChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.onSurface.withValues(alpha: 0.75);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: effectiveColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _TaskMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 156,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTaskBoard extends StatelessWidget {
  final bool hasTasks;
  final String query;
  final bool hideDone;

  const _EmptyTaskBoard({
    required this.hasTasks,
    required this.query,
    required this.hideDone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasTasks
                    ? Icons.filter_alt_off_rounded
                    : Icons.view_kanban_outlined,
                size: 42,
                color: scheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                hasTasks
                    ? 'Aucune tache ne correspond au filtre.'
                    : 'Aucune tache structuree pour ce channel.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                hasTasks
                    ? 'Essayez un autre mot-cle ou reaffichez les taches terminees.'
                    : 'Utilisez l extraction de mission ou les commandes de decision pour remplir ce board.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.4,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              if (hasTasks && (query.isNotEmpty || hideDone)) ...[
                const SizedBox(height: 14),
                Text(
                  [
                    if (query.isNotEmpty) 'filtre "$query"',
                    if (hideDone) 'terminees masquees',
                  ].join(' • '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskColumnConfig {
  final String status;
  final String title;
  final String emptyLabel;
  final IconData icon;
  final Color color;

  const _TaskColumnConfig({
    required this.status,
    required this.title,
    required this.emptyLabel,
    required this.icon,
    required this.color,
  });
}

class _TaskStatusOption {
  final String status;
  final String label;
  final IconData icon;

  const _TaskStatusOption({
    required this.status,
    required this.label,
    required this.icon,
  });
}

const List<_TaskStatusOption> _taskStatusOptions = [
  _TaskStatusOption(
    status: 'todo',
    label: 'Passer a faire',
    icon: Icons.radio_button_unchecked_rounded,
  ),
  _TaskStatusOption(
    status: 'in_progress',
    label: 'Passer en cours',
    icon: Icons.timelapse_rounded,
  ),
  _TaskStatusOption(
    status: 'blocked',
    label: 'Marquer bloquee',
    icon: Icons.block_outlined,
  ),
  _TaskStatusOption(
    status: 'done',
    label: 'Marquer terminee',
    icon: Icons.check_circle_outline_rounded,
  ),
];

int _compareTasks(WorkspaceTask left, WorkspaceTask right) {
  final leftDue = left.dueDate;
  final rightDue = right.dueDate;

  if (leftDue != null && rightDue != null) {
    final byDue = leftDue.compareTo(rightDue);
    if (byDue != 0) return byDue;
  } else if (leftDue != null) {
    return -1;
  } else if (rightDue != null) {
    return 1;
  }

  return right.updatedAt.compareTo(left.updatedAt);
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
