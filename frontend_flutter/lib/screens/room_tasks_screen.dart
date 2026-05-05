import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _activePulseFilter = 'all';
  String? _highlightedDecisionId;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  List<WorkspaceTask> _applyFilters(List<WorkspaceTask> tasks) {
    final normalizedQuery = _query.trim().toLowerCase();
    return tasks.where((task) {
      if (_hideDone && task.status == 'done') return false;
      if (!_matchesPulseFilter(task)) return false;
      if (normalizedQuery.isEmpty) return true;
      final haystack = [
        task.title,
        task.description,
        task.ownerName,
      ].join(' ').toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();
  }

  bool _matchesPulseFilter(WorkspaceTask task) {
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 3));
    switch (_activePulseFilter) {
      case 'urgent':
        if (task.status == 'done' || task.dueDate == null) return false;
        return !task.dueDate!.isAfter(soon);
      case 'blocked':
        return task.status == 'blocked';
      case 'unassigned':
        return task.ownerName.trim().isEmpty && task.ownerId.trim().isEmpty;
      default:
        return true;
    }
  }

  Future<void> _refreshExecutionPulse() async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await prov.refreshExecutionPulse();
    if (!mounted || ok) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          prov.actionError ?? 'Impossible de rafraichir le pulse execution',
        ),
      ),
    );
  }

  String _buildExecutionPulseDigest(RoomProvider prov) {
    final pulse = prov.executionPulse;
    if (pulse == null) return '';

    final buffer = StringBuffer()
      ..writeln('Digest execution - ${widget.roomName}')
      ..writeln('Genere le ${_formatDateTime(pulse.generatedAt)}')
      ..writeln('')
      ..writeln('Statut: ${_executionPulseLabel(pulse.status)}')
      ..writeln('Score: ${pulse.score}/100')
      ..writeln('Critiques: ${pulse.criticalCount}')
      ..writeln('Attentions: ${pulse.warningCount}')
      ..writeln('')
      ..writeln('Taches')
      ..writeln('- En retard: ${pulse.overdueTasks}')
      ..writeln('- A suivre sous 3 jours: ${pulse.dueSoonTasks}')
      ..writeln('- Bloquees: ${pulse.blockedTasks}')
      ..writeln('- Sans owner: ${pulse.unassignedTasks}')
      ..writeln('')
      ..writeln('Decisions')
      ..writeln('- En retard: ${pulse.overdueDecisions}')
      ..writeln('- A suivre sous 3 jours: ${pulse.dueSoonDecisions}')
      ..writeln('- Sans owner: ${pulse.decisionsWithoutOwner}')
      ..writeln('- En revue stale: ${pulse.staleReviewDecisions}');

    if (pulse.recommendations.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('Recommandations');
      for (final item in pulse.recommendations.take(5)) {
        buffer.writeln('- $item');
      }
    }

    if (pulse.focusItems.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('A traiter maintenant');
      for (final item in pulse.focusItems.take(5)) {
        final dueLabel =
            item.dueDate == null ? '' : ' - ${_formatDate(item.dueDate!)}';
        final ownerLabel =
            item.ownerName.trim().isEmpty ? '' : ' - ${item.ownerName.trim()}';
        buffer.writeln(
          '- ${item.kind == 'decision' ? 'Decision' : 'Tache'}: ${item.title}$ownerLabel$dueLabel',
        );
      }
    }

    return buffer.toString().trimRight();
  }

  Future<void> _showPulseDigestDialog() async {
    final prov = context.read<RoomProvider>();
    final pulse = prov.executionPulse;
    if (pulse == null) return;

    final digest = _buildExecutionPulseDigest(prov);
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Digest execution'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              digest,
              style: const TextStyle(height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: digest));
              if (!mounted || !ctx.mounted) return;
              Navigator.of(ctx).pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Digest execution copie')),
              );
            },
            icon: const Icon(Icons.copy_all_rounded, size: 18),
            label: const Text('Copier le digest'),
          ),
        ],
      ),
    );
  }

  void _handlePulseFilterChange(String filter) {
    setState(() {
      _activePulseFilter = filter;
      if (filter != 'all') {
        _highlightedDecisionId = null;
      }
    });
  }

  void _handlePulseFocusItemTap(ExecutionPulseFocusItem item) {
    if (item.kind == 'decision') {
      setState(() {
        _highlightedDecisionId = item.itemId;
        _activePulseFilter = 'all';
        _query = '';
        _queryCtrl.clear();
      });
      return;
    }

    setState(() {
      _highlightedDecisionId = null;
      _activePulseFilter = 'all';
      _query = item.title;
      _queryCtrl.text = item.title;
      _queryCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _queryCtrl.text.length),
      );
    });
  }

  String _resolveCurrentDisplayName(RoomProvider prov) {
    final myUserId = prov.myUserId;
    final room = prov.currentRoom;
    if (myUserId != null && room != null) {
      final member = room.members.where((item) => item.userId == myUserId);
      if (member.isNotEmpty) {
        final displayName = member.first.displayName.trim();
        if (displayName.isNotEmpty) return displayName;
      }
    }
    return 'Moi';
  }

  Future<DateTime?> _pickPulseDueDate() {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
  }

  Future<void> _handlePulseQuickAction(
    ExecutionPulseFocusItem item,
    String actionId,
  ) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (item.kind == 'decision') {
      final decision = prov.decisions.where((entry) => entry.id == item.itemId);
      if (decision.isEmpty) return;

      WorkspaceDecision? updated;
      if (actionId == 'assign_self') {
        updated = await prov.updateDecision(
          decision.first,
          ownerName: _resolveCurrentDisplayName(prov),
        );
      } else if (actionId == 'start_review') {
        updated = await prov.updateDecision(
          decision.first,
          status: 'review',
        );
      } else if (actionId == 'approve') {
        updated = await prov.updateDecision(
          decision.first,
          status: 'approved',
        );
      } else if (actionId == 'set_due_tomorrow') {
        final selectedDueDate = await _pickPulseDueDate();
        if (selectedDueDate == null) return;
        updated = await prov.updateDecision(
          decision.first,
          dueDate: selectedDueDate,
        );
      } else if (actionId == 'postpone_7d') {
        final base = item.dueDate ?? DateTime.now();
        updated = await prov.updateDecision(
          decision.first,
          dueDate: base.add(const Duration(days: 7)),
        );
      } else if (actionId == 'clear_due_date') {
        updated = await prov.updateDecision(
          decision.first,
          clearDueDate: true,
        );
      }

      if (!mounted) return;
      if (updated == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              prov.actionError ?? 'Impossible d appliquer l action rapide',
            ),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Decision mise a jour depuis le pulse')),
      );
      return;
    }

    final task = prov.tasks.where((entry) => entry.id == item.itemId);
    if (task.isEmpty) return;

    WorkspaceTask? updated;
    if (actionId == 'assign_self') {
      updated = await prov.updateTask(
        task.first,
        ownerName: _resolveCurrentDisplayName(prov),
      );
    } else if (actionId == 'unblock') {
      updated = await prov.updateTask(
        task.first,
        status: 'in_progress',
      );
    } else if (actionId == 'set_due_tomorrow') {
      final selectedDueDate = await _pickPulseDueDate();
      if (selectedDueDate == null) return;
      updated = await prov.updateTask(
        task.first,
        dueDate: selectedDueDate,
      );
    } else if (actionId == 'postpone_7d') {
      final base = item.dueDate ?? DateTime.now();
      updated = await prov.updateTask(
        task.first,
        dueDate: base.add(const Duration(days: 7)),
      );
    } else if (actionId == 'clear_due_date') {
      updated = await prov.updateTask(
        task.first,
        clearDueDate: true,
      );
    }

    if (!mounted) return;
    if (updated == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            prov.actionError ?? 'Impossible d appliquer l action rapide',
          ),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Tache mise a jour depuis le pulse')),
    );
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

  Future<void> _showCreateDecisionDialog() async {
    final titleCtrl = TextEditingController();
    final summaryCtrl = TextEditingController();
    bool saving = false;
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Creer une decision'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  enabled: !saving,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Titre *',
                    hintText: 'Ex: Approuver le budget Q2',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: summaryCtrl,
                  enabled: !saving,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Resume',
                    hintText: 'Resumer la decision et le contexte',
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
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Le titre est requis'),
                          ),
                        );
                        return;
                      }

                      setState(() => saving = true);
                      final created = await prov.createDecision(
                        title: title,
                        summary: summaryCtrl.text.trim(),
                        sourceType: 'manual',
                      );
                      if (!mounted || !ctx.mounted) return;
                      if (created == null) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              prov.actionError ??
                                  'Impossible de creer la decision',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Decision creee')),
                      );
                    },
              child: Text(saving ? 'Creation...' : 'Creer la decision'),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    summaryCtrl.dispose();
  }

  Future<void> _showCreateTaskDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ownerCtrl = TextEditingController();
    DateTime? dueDate;
    bool saving = false;
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Creer une tache'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  enabled: !saving,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Titre *',
                    hintText: 'Ex: Preparer le brief client',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  enabled: !saving,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Contexte ou instructions optionnelles',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ownerCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Responsable',
                    hintText: 'Nom de la personne assignee',
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
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                          );
                          if (picked == null || !ctx.mounted) return;
                          setState(() => dueDate = picked);
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
                            dueDate == null
                                ? 'Aucune date'
                                : '${dueDate!.day.toString().padLeft(2, '0')}/${dueDate!.month.toString().padLeft(2, '0')}/${dueDate!.year}',
                          ),
                        ),
                        if (dueDate != null)
                          IconButton(
                            onPressed: saving
                                ? null
                                : () => setState(() => dueDate = null),
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
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Le titre est requis')),
                        );
                        return;
                      }

                      setState(() => saving = true);
                      final created = await prov.createTask(
                        title: title,
                        description: descCtrl.text.trim(),
                        ownerName: ownerCtrl.text.trim(),
                        dueDate: dueDate,
                      );
                      if (!mounted || !ctx.mounted) return;
                      if (created == null) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              prov.actionError ??
                                  'Impossible de creer la tache',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Tache creee')),
                      );
                    },
              child: Text(saving ? 'Creation...' : 'Creer la tache'),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    descCtrl.dispose();
    ownerCtrl.dispose();
  }

  Future<void> _showDecisionWorkflowDialog(WorkspaceDecision decision) async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ownerCtrl = TextEditingController(text: decision.ownerName);
    String status = decision.status;
    DateTime? dueDate = decision.dueDate;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Workflow de decision'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    decision.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    items: _decisionStatusOptions
                        .map(
                          (option) => DropdownMenuItem<String>(
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
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            status = value;
                          },
                    decoration: const InputDecoration(
                      labelText: 'Statut',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ownerCtrl,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'Responsable',
                      hintText: 'Nom du proprietaire de la decision',
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
                                const Duration(days: 730),
                              ),
                            );
                            if (picked == null || !ctx.mounted) return;
                            setState(() => dueDate = picked);
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
                              dueDate == null
                                  ? 'Aucune date'
                                  : _formatDate(dueDate!),
                            ),
                          ),
                          if (dueDate != null)
                            IconButton(
                              onPressed: saving
                                  ? null
                                  : () => setState(() => dueDate = null),
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
                      final updated = await prov.updateDecision(
                        decision,
                        status: status,
                        ownerName: ownerCtrl.text.trim(),
                        dueDate: dueDate,
                        clearDueDate: dueDate == null,
                      );
                      if (!mounted || !ctx.mounted) return;
                      if (updated == null) {
                        setState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              prov.actionError ??
                                  'Impossible de mettre a jour la decision',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Decision mise a jour'),
                        ),
                      );
                    },
              child: Text(saving ? 'Sauvegarde...' : 'Sauvegarder'),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a dialog listing every recorded decision and lets the user pick one
  /// then define 1-3 tasks to generate from it. Calls convertDecisionToTasks().
  Future<void> _showConvertDecisionDialog() async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final decisions = prov.decisions;

    if (decisions.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune decision enregistree. Creez d\'abord une decision ou utilisez l\'extraction IA.',
          ),
        ),
      );
      return;
    }

    // Step 1 – pick a decision
    WorkspaceDecision? picked;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Choisir une decision'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: decisions.map((d) {
                  final selected = picked?.id == d.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: selected
                          ? Theme.of(ctx).colorScheme.primaryContainer
                          : Theme.of(ctx).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => picked = d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: Theme.of(ctx).colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (d.summary.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        d.summary,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: picked == null ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Suivant'),
            ),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;
    final decision = picked!;

    // Step 2 – define tasks for the chosen decision
    final taskTitleCtrls = [TextEditingController()];
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void addRow() {
            if (taskTitleCtrls.length < 6) {
              setState(() => taskTitleCtrls.add(TextEditingController()));
            }
          }

          return AlertDialog(
            title: Text(
              'Taches pour : ${decision.title}',
              overflow: TextOverflow.ellipsis,
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Definissez les taches a cree pour cette decision (max 6)',
                      style: TextStyle(
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...taskTitleCtrls.asMap().entries.map((entry) {
                      final i = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                enabled: !saving,
                                decoration: InputDecoration(
                                  labelText: 'Tache ${i + 1}',
                                  hintText: 'Ex: Rediger le brief',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            if (taskTitleCtrls.length > 1) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: saving
                                    ? null
                                    : () => setState(
                                          () => taskTitleCtrls.removeAt(i),
                                        ),
                                icon: const Icon(Icons.remove_circle_outline),
                                tooltip: 'Supprimer',
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    if (taskTitleCtrls.length < 6)
                      TextButton.icon(
                        onPressed: saving ? null : addRow,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Ajouter une tache'),
                      ),
                  ],
                ),
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
                        final titles = taskTitleCtrls
                            .map((c) => c.text.trim())
                            .where((t) => t.isNotEmpty)
                            .toList();
                        if (titles.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Ajoutez au moins une tache',
                              ),
                            ),
                          );
                          return;
                        }
                        setState(() => saving = true);
                        final created = await prov.convertDecisionToTasks(
                          decision,
                          taskDrafts: titles
                              .map((t) => <String, dynamic>{'title': t})
                              .toList(),
                        );
                        if (!mounted || !ctx.mounted) return;
                        if (created == null) {
                          setState(() => saving = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                prov.actionError ??
                                    'Impossible de convertir la decision',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.of(ctx).pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              '${created.length} tache${created.length > 1 ? 's creees' : ' creee'} a partir de la decision',
                            ),
                          ),
                        );
                      },
                child: Text(saving ? 'Creation...' : 'Creer les taches'),
              ),
            ],
          );
        },
      ),
    );
    // Note: taskTitleCtrls controllers go out of scope here and are GC'd.
    // We intentionally don't dispose them manually: after Navigator.pop(),
    // a post-frame rebuild of the dismissed StatefulBuilder would trigger
    // "used after dispose" in debug mode.
  }

  /// AI-extracts decisions + tasks from chat history, shows a preview,
  /// then optionally persists everything.
  Future<void> _showExtractFromChatDialog() async {
    final prov = context.read<RoomProvider>();
    final messenger = ScaffoldMessenger.of(context);

    bool loading = true;
    bool saving = false;
    DecisionExtractionResult? preview;
    String? loadError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          // Kick off preview load once
          if (loading && preview == null && loadError == null) {
            prov.extractDecisionsFromChat(persist: false).then((result) {
              if (!ctx.mounted) return;
              setState(() {
                loading = false;
                preview = result;
                if (result == null) loadError = prov.actionError ?? 'Erreur';
              });
            });
          }

          final scheme = Theme.of(ctx).colorScheme;

          return AlertDialog(
            title: const Text('Extraction IA — decisions et taches'),
            content: SizedBox(
              width: 560,
              child: loading
                  ? const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : loadError != null
                      ? Text(
                          'Erreur : $loadError',
                          style: TextStyle(color: scheme.error),
                        )
                      : preview == null || (preview!.extracted.isEmpty)
                          ? const Text(
                              'Aucune decision detectee dans les messages recents.',
                            )
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${preview!.extracted.length} decision${preview!.extracted.length > 1 ? "s" : ""} detectee${preview!.extracted.length > 1 ? "s" : ""}',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...preview!.extracted.map((d) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: scheme.primary
                                              .withValues(alpha: 0.18),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.folder_outlined,
                                                size: 16,
                                                color: scheme.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  d.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (d.summary.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              d.summary,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.7),
                                              ),
                                            ),
                                          ],
                                          if (d.tasks.isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            ...d.tasks.map(
                                              (t) => Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .radio_button_unchecked_rounded,
                                                      size: 14,
                                                      color: scheme.onSurface
                                                          .withValues(
                                                        alpha: 0.5,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        t.title,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: scheme
                                                              .onSurface
                                                              .withValues(
                                                            alpha: 0.85,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
            ),
            actions: [
              TextButton(
                onPressed:
                    (saving || loading) ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
              if (!loading &&
                  loadError == null &&
                  (preview?.extracted.isNotEmpty ?? false))
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() => saving = true);
                          final result = await prov.extractDecisionsFromChat(
                            persist: true,
                          );
                          if (!mounted || !ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          if (result == null) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  prov.actionError ??
                                      'Erreur lors de la sauvegarde',
                                ),
                              ),
                            );
                          } else {
                            final n = result.decisions.length;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$n decision${n > 1 ? "s" : ""} et taches sauvegardees',
                                ),
                              ),
                            );
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt_rounded, size: 18),
                  label: Text(saving ? 'Sauvegarde...' : 'Sauvegarder tout'),
                ),
            ],
          );
        },
      ),
    );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'Extraire decisions et taches par IA',
            onPressed: _showExtractFromChatDialog,
          ),
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Convertir une decision en taches',
            onPressed: _showConvertDecisionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Creer une decision',
            onPressed: _showCreateDecisionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Creer une tache',
            onPressed: _showCreateTaskDialog,
          ),
        ],
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
                    if (prov.executionPulse != null) ...[
                      const SizedBox(height: 16),
                      _ExecutionPulseCard(
                        pulse: prov.executionPulse!,
                        activeFilter: _activePulseFilter,
                        loading: prov.loadingExecutionPulse,
                        onOpenDigest: _showPulseDigestDialog,
                        onRefresh: _refreshExecutionPulse,
                        onFilterSelected: _handlePulseFilterChange,
                        onFocusItemTap: _handlePulseFocusItemTap,
                        onQuickAction: _handlePulseQuickAction,
                      ),
                    ],
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
              if (prov.decisions.isNotEmpty)
                _DecisionsPanel(
                  decisions: prov.decisions,
                  tasks: prov.tasks,
                  onConvert: _showConvertDecisionDialog,
                  onEditDecision: _showDecisionWorkflowDialog,
                  highlightedDecisionId: _highlightedDecisionId,
                ),
              Expanded(child: board),
            ],
          );
        },
      ),
    );
  }
}

class _DecisionsPanel extends StatefulWidget {
  final List<WorkspaceDecision> decisions;
  final List<WorkspaceTask> tasks;
  final VoidCallback onConvert;
  final ValueChanged<WorkspaceDecision> onEditDecision;
  final String? highlightedDecisionId;

  const _DecisionsPanel({
    required this.decisions,
    required this.tasks,
    required this.onConvert,
    required this.onEditDecision,
    this.highlightedDecisionId,
  });

  @override
  State<_DecisionsPanel> createState() => _DecisionsPanelState();
}

class _DecisionsPanelState extends State<_DecisionsPanel> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _DecisionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedDecisionId != null &&
        widget.highlightedDecisionId != oldWidget.highlightedDecisionId) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decisionCount = widget.decisions.length;
    final linkedTaskCount =
        widget.tasks.where((t) => t.decisionId.isNotEmpty).length;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.secondary.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: scheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$decisionCount decision${decisionCount > 1 ? "s" : ""}'
                        '  •  $linkedTaskCount tache${linkedTaskCount > 1 ? "s" : ""} liee${linkedTaskCount > 1 ? "s" : ""}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.onConvert,
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: const Text('Convertir'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: scheme.onSecondaryContainer.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            // Expanded list
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: widget.decisions.map((d) {
                    final taskCount =
                        widget.tasks.where((t) => t.decisionId == d.id).length;
                    final highlighted = d.id == widget.highlightedDecisionId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: highlighted
                              ? scheme.primaryContainer.withValues(alpha: 0.45)
                              : scheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: highlighted
                              ? Border.all(
                                  color: scheme.primary.withValues(alpha: 0.35),
                                )
                              : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (d.summary.isNotEmpty)
                                    Text(
                                      d.summary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _DecisionMetaChip(
                                        label: _decisionStatusLabel(d.status),
                                        icon: _decisionStatusIcon(d.status),
                                        color: _decisionStatusColor(
                                          d.status,
                                          scheme,
                                        ),
                                      ),
                                      if (d.ownerName.isNotEmpty)
                                        _DecisionMetaChip(
                                          label: d.ownerName,
                                          icon: Icons.person_outline_rounded,
                                          color: scheme.primary,
                                        ),
                                      if (d.dueDate != null)
                                        _DecisionMetaChip(
                                          label: _formatDate(d.dueDate!),
                                          icon: Icons.event_outlined,
                                          color: scheme.secondary,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Chip(
                                  label: Text(
                                    '$taskCount tache${taskCount != 1 ? "s" : ""}',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                const SizedBox(height: 4),
                                IconButton(
                                  tooltip: 'Editer workflow',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => widget.onEditDecision(d),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
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

class _DecisionMetaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _DecisionMetaChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
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

class _ExecutionPulseCard extends StatelessWidget {
  final ExecutionPulse pulse;
  final String activeFilter;
  final bool loading;
  final VoidCallback onOpenDigest;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onFilterSelected;
  final ValueChanged<ExecutionPulseFocusItem> onFocusItemTap;
  final Future<void> Function(ExecutionPulseFocusItem item, String actionId)
      onQuickAction;

  const _ExecutionPulseCard({
    required this.pulse,
    required this.activeFilter,
    required this.loading,
    required this.onOpenDigest,
    required this.onRefresh,
    required this.onFilterSelected,
    required this.onFocusItemTap,
    required this.onQuickAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = _executionPulseColor(pulse.status, scheme);
    final statusLabel = _executionPulseLabel(pulse.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.monitor_heart_outlined, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Execution pulse',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _DecisionMetaChip(
                          label: statusLabel,
                          icon: _executionPulseIcon(pulse.status),
                          color: tone,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Ouvrir le digest execution',
                          onPressed: onOpenDigest,
                          icon: const Icon(
                            Icons.summarize_outlined,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Rafraichir le pulse execution',
                          onPressed: loading ? null : onRefresh,
                          icon: loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Score ${pulse.score} • ${pulse.criticalCount} critique${pulse.criticalCount > 1 ? 's' : ''} • ${pulse.warningCount} attention${pulse.warningCount > 1 ? 's' : ''}',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DecisionMetaChip(
                label: '${pulse.overdueTasks} taches en retard',
                icon: Icons.event_busy_outlined,
                color: pulse.overdueTasks > 0 ? scheme.error : scheme.outline,
              ),
              _DecisionMetaChip(
                label: '${pulse.blockedTasks} bloquees',
                icon: Icons.block_outlined,
                color: pulse.blockedTasks > 0 ? scheme.error : scheme.outline,
              ),
              _DecisionMetaChip(
                label: '${pulse.overdueDecisions} decisions en retard',
                icon: Icons.priority_high_rounded,
                color:
                    pulse.overdueDecisions > 0 ? scheme.error : scheme.outline,
              ),
              _DecisionMetaChip(
                label: '${pulse.decisionsWithoutOwner} decisions sans owner',
                icon: Icons.person_search_outlined,
                color: pulse.decisionsWithoutOwner > 0
                    ? scheme.tertiary
                    : scheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PulseFilterChip(
                label: 'Tout',
                selected: activeFilter == 'all',
                onSelected: () => onFilterSelected('all'),
              ),
              _PulseFilterChip(
                label: 'Urgent',
                selected: activeFilter == 'urgent',
                onSelected: () => onFilterSelected('urgent'),
              ),
              _PulseFilterChip(
                label: 'Bloquees',
                selected: activeFilter == 'blocked',
                onSelected: () => onFilterSelected('blocked'),
              ),
              _PulseFilterChip(
                label: 'Sans owner',
                selected: activeFilter == 'unassigned',
                onSelected: () => onFilterSelected('unassigned'),
              ),
            ],
          ),
          if (pulse.recommendations.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...pulse.recommendations.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.subdirectory_arrow_right_rounded,
                            size: 18, color: tone),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              height: 1.3,
                              color: scheme.onSurface.withValues(alpha: 0.82),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (pulse.focusItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'A traiter maintenant',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withValues(alpha: 0.82),
              ),
            ),
            const SizedBox(height: 8),
            ...pulse.focusItems.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onFocusItemTap(item),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                item.kind == 'decision'
                                    ? Icons.folder_outlined
                                    : Icons.checklist_rtl_rounded,
                                size: 18,
                                color: item.severity == 'critical'
                                    ? scheme.error
                                    : scheme.tertiary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.subtitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.68),
                                      ),
                                    ),
                                    if (_pulseQuickActionLabel(item) !=
                                        null) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: () => onQuickAction(
                                          item,
                                          _pulseQuickActionId(item)!,
                                        ),
                                        icon: Icon(
                                          _pulseQuickActionIcon(item),
                                          size: 16,
                                        ),
                                        label:
                                            Text(_pulseQuickActionLabel(item)!),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(0, 32),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                          alignment: Alignment.centerLeft,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.dueDate != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        _formatDate(item.dueDate!),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: item.severity == 'critical'
                                              ? scheme.error
                                              : scheme.tertiary,
                                        ),
                                      ),
                                    ),
                                  _PulseDateMenuButton(
                                    item: item,
                                    onAction: onQuickAction,
                                    scheme: scheme,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
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
      ],
    );
  }
}

class _PulseFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _PulseFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PulseDateMenuButton extends StatelessWidget {
  final ExecutionPulseFocusItem item;
  final Future<void> Function(ExecutionPulseFocusItem, String) onAction;
  final ColorScheme scheme;

  const _PulseDateMenuButton({
    required this.item,
    required this.onAction,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final hasDue = item.dueDate != null;
    return PopupMenuButton<String>(
      tooltip: 'Gerer l echeance',
      padding: EdgeInsets.zero,
      icon: Icon(
        hasDue ? Icons.edit_calendar_rounded : Icons.calendar_month_outlined,
        size: 18,
        color: scheme.onSurface.withValues(alpha: 0.55),
      ),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'set_due_tomorrow',
          child: Row(
            children: [
              const Icon(Icons.event_available_rounded, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hasDue ? 'Modifier l echeance' : 'Fixer echeance',
                ),
              ),
            ],
          ),
        ),
        if (hasDue) ...[
          const PopupMenuItem<String>(
            value: 'postpone_7d',
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 16),
                SizedBox(width: 8),
                Flexible(child: Text('Reporter +7 jours')),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'clear_due_date',
            child: Row(
              children: [
                Icon(Icons.event_busy_rounded, size: 16),
                SizedBox(width: 8),
                Flexible(child: Text('Retirer echeance')),
              ],
            ),
          ),
        ],
      ],
      onSelected: (actionId) => onAction(item, actionId),
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

class _DecisionStatusOption {
  final String status;
  final String label;
  final IconData icon;

  const _DecisionStatusOption({
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

const List<_DecisionStatusOption> _decisionStatusOptions = [
  _DecisionStatusOption(
    status: 'draft',
    label: 'Brouillon',
    icon: Icons.edit_note_rounded,
  ),
  _DecisionStatusOption(
    status: 'review',
    label: 'En revue',
    icon: Icons.rate_review_outlined,
  ),
  _DecisionStatusOption(
    status: 'approved',
    label: 'Approuvee',
    icon: Icons.verified_rounded,
  ),
  _DecisionStatusOption(
    status: 'implemented',
    label: 'Implantee',
    icon: Icons.task_alt_rounded,
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

String _formatDateTime(DateTime date) {
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)} $hh:$mm';
}

String _decisionStatusLabel(String status) {
  switch (status) {
    case 'review':
      return 'En revue';
    case 'approved':
      return 'Approuvee';
    case 'implemented':
      return 'Implantee';
    case 'draft':
    default:
      return 'Brouillon';
  }
}

IconData _decisionStatusIcon(String status) {
  switch (status) {
    case 'review':
      return Icons.rate_review_outlined;
    case 'approved':
      return Icons.verified_rounded;
    case 'implemented':
      return Icons.task_alt_rounded;
    case 'draft':
    default:
      return Icons.edit_note_rounded;
  }
}

Color _decisionStatusColor(String status, ColorScheme scheme) {
  switch (status) {
    case 'review':
      return scheme.tertiary;
    case 'approved':
      return const Color(0xFF2E8B57);
    case 'implemented':
      return scheme.primary;
    case 'draft':
    default:
      return scheme.outline;
  }
}

String _executionPulseLabel(String status) {
  switch (status) {
    case 'critical':
      return 'Critique';
    case 'attention':
      return 'Attention';
    case 'on_track':
    default:
      return 'Sous controle';
  }
}

String? _pulseQuickActionId(ExecutionPulseFocusItem item) {
  if (item.ownerName.trim().isEmpty) {
    return 'assign_self';
  }
  if (item.kind == 'decision') {
    if (item.status == 'draft') return 'start_review';
    if (item.status == 'review') return 'approve';
  }
  if (item.status == 'blocked') return 'unblock';
  return null;
}

String? _pulseQuickActionLabel(ExecutionPulseFocusItem item) {
  switch (_pulseQuickActionId(item)) {
    case 'assign_self':
      return 'Me l assigner';
    case 'start_review':
      return 'Passer en revue';
    case 'approve':
      return 'Approuver';
    case 'unblock':
      return 'Relancer';
    default:
      return null;
  }
}

IconData _pulseQuickActionIcon(ExecutionPulseFocusItem item) {
  switch (_pulseQuickActionId(item)) {
    case 'assign_self':
      return Icons.person_add_alt_rounded;
    case 'start_review':
      return Icons.rate_review_outlined;
    case 'approve':
      return Icons.verified_rounded;
    case 'unblock':
      return Icons.play_arrow_rounded;
    default:
      return Icons.bolt_rounded;
  }
}

IconData _executionPulseIcon(String status) {
  switch (status) {
    case 'critical':
      return Icons.warning_amber_rounded;
    case 'attention':
      return Icons.visibility_outlined;
    case 'on_track':
    default:
      return Icons.task_alt_rounded;
  }
}

Color _executionPulseColor(String status, ColorScheme scheme) {
  switch (status) {
    case 'critical':
      return scheme.error;
    case 'attention':
      return scheme.tertiary;
    case 'on_track':
    default:
      return const Color(0xFF2E8B57);
  }
}
