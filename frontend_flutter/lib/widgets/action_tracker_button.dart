import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/action_task.dart';
import '../providers/action_task_provider.dart';

/// Floating button + badge showing pending action count.
/// Tapping opens the full task sheet.
class ActionTrackerButton extends StatelessWidget {
  final String deliverableTitle;
  final Map<String, dynamic>? deliveryPlan;
  final List<String> steps;

  const ActionTrackerButton({
    super.key,
    required this.deliverableTitle,
    required this.deliveryPlan,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ActionTaskProvider>();
    final pending = provider.pendingCount;
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Actions à faire',
      child: TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.primary,
        ),
        icon: Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending', style: const TextStyle(fontSize: 10)),
          child: const Icon(Icons.checklist_rounded, size: 18),
        ),
        label: const Text('Actions', style: TextStyle(fontSize: 13)),
        onPressed: () => _openSheet(context),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ActionTaskProvider>(),
        child: _ActionTasksSheet(
          deliverableTitle: deliverableTitle,
          deliveryPlan: deliveryPlan,
          steps: steps,
        ),
      ),
    );
  }
}

class _ActionTasksSheet extends StatelessWidget {
  final String deliverableTitle;
  final Map<String, dynamic>? deliveryPlan;
  final List<String> steps;

  const _ActionTasksSheet({
    required this.deliverableTitle,
    required this.deliveryPlan,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ActionTaskProvider>();
    final scheme = Theme.of(context).colorScheme;
    final tasks = provider.tasks;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.checklist_rounded, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Actions à suivre',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                // Import from plan
                if (tasks.isEmpty || tasks.length < 20)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label:
                        const Text('Importer', style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      await provider.importFromPlan(
                        title: deliverableTitle,
                        deliveryPlan: deliveryPlan,
                        steps: steps,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Actions importées du plan.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                // Export CSV
                if (tasks.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.share_rounded,
                        size: 18, color: scheme.primary),
                    tooltip: 'Exporter CSV',
                    onPressed: () => _exportCsv(context, provider),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Task list
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.checklist_outlined,
                              size: 48,
                              color: scheme.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Text(
                            'Aucune action pour l\'instant.',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.45),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: () async {
                              await provider.importFromPlan(
                                title: deliverableTitle,
                                deliveryPlan: deliveryPlan,
                                steps: steps,
                              );
                            },
                            child: const Text('Importer depuis le plan'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) =>
                        _TaskTile(task: tasks[i], provider: provider),
                  ),
          ),
          // Footer — clear all
          if (tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${provider.tasks.where((t) => t.done).length}/${tasks.length} fait',
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.45)),
                  ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                        visualDensity: VisualDensity.compact),
                    onPressed: () async {
                      await provider.clearAll();
                    },
                    child: const Text('Tout effacer',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(
      BuildContext context, ActionTaskProvider provider) async {
    final csv = provider.toCsv();
    try {
      await Share.share(
        csv,
        subject: 'Actions — $deliverableTitle',
      );
    } catch (_) {
      // fallback: copy to clipboard
      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV copié dans le presse-papier.')),
        );
      }
    }
  }
}

class _TaskTile extends StatefulWidget {
  final ActionTask task;
  final ActionTaskProvider provider;
  const _TaskTile({required this.task, required this.provider});

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  bool _editingOwner = false;
  late final TextEditingController _ownerCtrl;

  @override
  void initState() {
    super.initState();
    _ownerCtrl = TextEditingController(text: widget.task.owner ?? '');
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    super.dispose();
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.p0:
        return Colors.red.shade600;
      case TaskPriority.p1:
        return Colors.orange.shade600;
      case TaskPriority.p2:
        return Colors.green.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: t.done
            ? scheme.surfaceContainerLow.withValues(alpha: 0.5)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: t.done,
                  onChanged: (_) => widget.provider.toggleDone(t.id),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.done
                          ? scheme.onSurface.withValues(alpha: 0.35)
                          : scheme.onSurface,
                      decoration: t.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Priority badge
                      PopupMenuButton<TaskPriority>(
                        padding: EdgeInsets.zero,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _priorityColor(t.priority)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            t.priorityLabel,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _priorityColor(t.priority)),
                          ),
                        ),
                        onSelected: (p) =>
                            widget.provider.updatePriority(t.id, p),
                        itemBuilder: (_) => TaskPriority.values
                            .map((p) => PopupMenuItem(
                                  value: p,
                                  child: Text(p.name.toUpperCase()),
                                ))
                            .toList(),
                      ),
                      const SizedBox(width: 8),
                      // Owner
                      _editingOwner
                          ? SizedBox(
                              width: 110,
                              height: 26,
                              child: TextField(
                                controller: _ownerCtrl,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Responsable',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 4),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 11),
                                onSubmitted: (v) {
                                  widget.provider.updateOwner(t.id, v);
                                  setState(() => _editingOwner = false);
                                },
                              ),
                            )
                          : GestureDetector(
                              onTap: () => setState(() => _editingOwner = true),
                              child: Text(
                                t.owner?.isNotEmpty == true
                                    ? '👤 ${t.owner}'
                                    : '+ responsable',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: t.owner?.isNotEmpty == true
                                      ? scheme.onSurface.withValues(alpha: 0.65)
                                      : scheme.primary.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                      if ((t.dueDate ?? '').isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '📅 ${t.dueDate}',
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Delete
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded,
                  size: 16, color: scheme.onSurface.withValues(alpha: 0.3)),
              onPressed: () => widget.provider.deleteTask(t.id),
            ),
          ],
        ),
      ),
    );
  }
}
