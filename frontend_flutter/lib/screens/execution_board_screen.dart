import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/room.dart';
import '../providers/room_provider.dart';

/// ExecutionBoard: Kanban-style view for decisions & tasks.
/// Columns: Todo | In Progress | Blocked | Done
class ExecutionBoardScreen extends StatefulWidget {
  const ExecutionBoardScreen({super.key});

  @override
  State<ExecutionBoardScreen> createState() => _ExecutionBoardScreenState();
}

class _ExecutionBoardScreenState extends State<ExecutionBoardScreen> {
  late Map<String, List<WorkspaceTask>> _tasksByStatus;
  late Map<String, List<WorkspaceDecision>> _decisionsByStatus;

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
    final prov = context.read<RoomProvider>();
    await prov.openRoom(room);
    if (!mounted) return;
    setState(() {
      _rebuildMaps();
    });
  }

  Future<void> _createGeneralRoom() async {
    final prov = context.read<RoomProvider>();
    final room = await prov.createRoom(
      name: 'General',
      displayName: prov.myUserId ?? 'Utilisateur',
    );
    if (room == null) return;
    await _openRoom(room);
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
    final prov = context.read<RoomProvider>();
    await prov.updateTask(task, status: newStatus);
    setState(() {
      _rebuildMaps();
    });
  }

  Future<void> _handleDecisionStatusChange(
    WorkspaceDecision decision,
    String newStatus,
  ) async {
    final prov = context.read<RoomProvider>();
    await prov.updateDecision(decision, status: newStatus);
    setState(() {
      _rebuildMaps();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoomProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (prov.currentRoom == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Execution Board')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selectionnez un channel pour afficher le Kanban.',
                style:
                    TextStyle(color: scheme.onSurface.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        prov.loadingRooms ? null : () => prov.loadRooms(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualiser'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _createGeneralRoom,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Creer General'),
                  ),
                ],
              ),
              if (prov.roomsError != null) ...[
                const SizedBox(height: 8),
                Text(
                  prov.roomsError!,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: prov.loadingRooms
                    ? const Center(child: CircularProgressIndicator())
                    : prov.rooms.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun channel disponible.',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: prov.rooms.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final room = prov.rooms[index];
                              return ListTile(
                                tileColor: scheme.surfaceContainerHighest,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                title: Text(room.name),
                                subtitle: Text('${room.memberCount} membre(s)'),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: () => _openRoom(room),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Execution Board'),
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tasks'),
              Tab(text: 'Decisions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TasksBoard(
              tasksByStatus: _tasksByStatus,
              onStatusChange: _handleStatusChange,
            ),
            _DecisionsBoard(
              decisionsByStatus: _decisionsByStatus,
              onStatusChange: _handleDecisionStatusChange,
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
    required this.tasksByStatus,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const columns = ['todo', 'in_progress', 'blocked', 'done'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: columns.length * 320.0,
        child: Row(
          children: columns.map((status) {
            final tasks = tasksByStatus[status] ?? [];
            return _KanbanColumn<WorkspaceTask>(
              title: _formatTaskStatus(status),
              count: tasks.length,
              items: tasks,
              statusOptions: ['todo', 'in_progress', 'blocked', 'done'],
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
    required this.decisionsByStatus,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const columns = ['draft', 'review', 'approved', 'implemented'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: columns.length * 320.0,
        child: Row(
          children: columns.map((status) {
            final decisions = decisionsByStatus[status] ?? [];
            return _KanbanColumn<WorkspaceDecision>(
              title: _formatDecisionStatus(status),
              count: decisions.length,
              items: decisions,
              statusOptions: ['draft', 'review', 'approved', 'implemented'],
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
      width: 320,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: columnColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: columnColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
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
                    child: Text(
                      'Vide',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
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

    return GestureDetector(
      onTap: () {
        _showCardMenu(context, scheme);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (ownerName.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                ownerName,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            if (dueDate != null) ...[
              const SizedBox(height: 6),
              Text(
                _formatDate(dueDate),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: dueDate.isBefore(DateTime.now())
                      ? scheme.error
                      : scheme.tertiary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _StatusChangeMenu(
              statusOptions: statusOptions,
              currentStatus: currentStatus,
              onStatusChange: (newStatus) {
                onStatusChange(item, newStatus);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCardMenu(BuildContext context, ColorScheme scheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Card actions: edit, delete (coming soon)'),
        duration: const Duration(milliseconds: 2000),
      ),
    );
  }
}

class _StatusChangeMenu extends StatelessWidget {
  final List<String> statusOptions;
  final String currentStatus;
  final Function(String) onStatusChange;

  const _StatusChangeMenu({
    required this.statusOptions,
    required this.currentStatus,
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
                  Text(status),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_drop_down_rounded, size: 14),
            SizedBox(width: 2),
            Text(
              'Change status',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
      return 'To Do';
    case 'in_progress':
      return 'In Progress';
    case 'blocked':
      return 'Blocked';
    case 'done':
      return 'Done';
    default:
      return status;
  }
}

String _formatDecisionStatus(String status) {
  switch (status) {
    case 'draft':
      return 'Draft';
    case 'review':
      return 'In Review';
    case 'approved':
      return 'Approved';
    case 'implemented':
      return 'Implemented';
    default:
      return status;
  }
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) {
    return 'Today';
  } else if (diff.inDays == -1) {
    return 'Tomorrow';
  } else if (diff.inDays < 0 && diff.inDays > -7) {
    return 'In ${-diff.inDays}d';
  } else if (diff.inDays > 0 && diff.inDays < 7) {
    return '${diff.inDays}d ago';
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
