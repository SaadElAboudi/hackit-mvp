import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';
import '../services/api_service.dart';

/// My Day: Daily execution cockpit showing priorities, blockers, and task status.
///
/// E1-03: My Day screen (Flutter)
/// - Top 3 priorities with risk scoring
/// - Blockers section
/// - Due today section
/// - Waiting for (tasks assigned to others)
/// - Action buttons: mark done, defer, ping owner, open context
class MyDayScreen extends StatefulWidget {
  const MyDayScreen({super.key});

  @override
  State<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends State<MyDayScreen> {
  final ApiService _apiService = ApiService.create();
  MyDayResponse? _myDay;
  bool _isLoading = true;
  String? _errorMessage;
  String? _lastRequestId;
  List<Map<String, dynamic>> _nudges = [];
  List<Map<String, dynamic>> _reminders = [];

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prov = context.read<RoomProvider>();
      await prov.ensureCurrentRoom(createIfMissing: false);

      final roomId = prov.currentRoom?.id;
      if (roomId == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Aucun salon selectionne. Ouvrez Salons d abord.';
        });
        return;
      }

      await Future.wait([
        _loadMyDayForRoom(roomId),
        _loadNudgesForRoom(roomId),
        _loadRemindersForRoom(roomId),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Echec du chargement de Mes priorites: $e';
      });
    }
  }

  Future<void> _loadMyDayForRoom(String roomId) async {
    try {
      final responseData = await _apiService.getMyDay(roomId);
      final response = MyDayResponse.fromJson(responseData);

      if (!mounted) return;

      setState(() {
        _myDay = response;
        _lastRequestId = response.requestId;
        _isLoading = false;
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _loadNudgesForRoom(String roomId) async {
    try {
      final nudges = await _apiService.getNudges(roomId);
      if (!mounted) return;
      setState(() => _nudges = nudges);
    } catch (e) {
      debugPrint('Error loading nudges: $e');
    }
  }

  Future<void> _loadRemindersForRoom(String roomId) async {
    try {
      final reminders = await _apiService.getReminders(roomId);
      if (!mounted) return;
      setState(() => _reminders = reminders);
    } catch (e) {
      debugPrint('Error loading reminders: $e');
    }
  }

  Future<void> _snoozeReminder(String reminderId, int minutes) async {
    try {
      final prov = context.read<RoomProvider>();
      final room = prov.currentRoom;
      if (room == null || reminderId.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rappel indisponible pour le report')),
        );
        return;
      }

      await _apiService.snoozeReminder(room.id, reminderId, minutes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rappel reporte de ${minutes}m')),
      );
      await _loadRemindersForRoom(room.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _dismissNudge(String nudgeId, {String reason = ''}) async {
    try {
      final prov = context.read<RoomProvider>();
      final room = prov.currentRoom;
      if (room == null || nudgeId.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suggestion introuvable')),
        );
        return;
      }

      await _apiService.dismissNudge(room.id, nudgeId, reason: reason);

      if (!mounted) return;
      setState(() {
        _nudges.removeWhere((n) => n['id'] == nudgeId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suggestion ignoree')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _markTaskDone(String taskId) async {
    try {
      final prov = context.read<RoomProvider>();
      final room = prov.currentRoom;
      if (room == null || taskId.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tache introuvable')),
        );
        return;
      }

      await _apiService.executeTaskAction(
        room.id,
        taskId,
        const {'type': 'mark_done'},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tache marquee comme faite')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _deferTask(String taskId) async {
    try {
      final prov = context.read<RoomProvider>();
      final room = prov.currentRoom;
      if (room == null || taskId.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tache introuvable')),
        );
        return;
      }

      final deferUntil = DateTime.now().add(const Duration(days: 1));
      await _apiService.executeTaskAction(
        room.id,
        taskId,
        {'type': 'defer', 'deferUntil': deferUntil.toIso8601String()},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tache reportee a demain')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _pingOwner(String taskId) async {
    if (taskId.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Responsable introuvable')),
      );
      return;
    }

    // E1-04: Action handler stub
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Responsable relance (E1-04 pending)')),
    );
  }

  Future<void> _openContext(String taskId) async {
    if (taskId.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contexte indisponible')),
      );
      return;
    }

    // Navigate to task detail screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ouverture du contexte pour la tache $taskId')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes priorites'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(_errorMessage!),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _refreshAll,
            child: const Text('Reessayer'),
          ),
          if (_lastRequestId != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Request ID: $_lastRequestId',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final myDay = _myDay;
    if (myDay == null) {
      return const Center(child: Text('Aucune donnee disponible'));
    }

    final totalItems =
        myDay.top3.length + myDay.blocked.length + myDay.dueToday.length;

    if (myDay.top3.isEmpty &&
        myDay.blocked.isEmpty &&
        myDay.dueToday.isEmpty &&
        myDay.waitingFor.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text(
                'Rien d urgent aujourd hui',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Vos priorites sont a jour pour le moment.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Generation de priorites a affiner'),
                    ),
                  );
                },
                child: const Text('Recalculer mes priorites'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDailyBrief(myDay, totalItems),
              const SizedBox(height: 20),
              if (_nudges.isNotEmpty) ...[
                _buildNudgesSection(),
                const SizedBox(height: 24),
              ],
              if (_reminders.isNotEmpty) ...[
                _buildRemindersSection(),
                const SizedBox(height: 24),
              ],
              _buildSection('Top 3 priorites', myDay.top3, Colors.blue),
              const SizedBox(height: 24),
              _buildSection('Blocages', myDay.blocked, Colors.red),
              const SizedBox(height: 24),
              _buildSection(
                  'A faire aujourd hui', myDay.dueToday, Colors.orange),
              const SizedBox(height: 24),
              _buildSection('En attente', myDay.waitingFor, Colors.purple),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyBrief(MyDayResponse myDay, int totalItems) {
    final blockedCount = myDay.blocked.length;
    final dueTodayCount = myDay.dueToday.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.indigo.shade600,
            Colors.indigo.shade400,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan d execution du jour',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '$totalItems elements actifs a piloter maintenant.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildKpiChip(
                icon: Icons.flag,
                label: '${myDay.top3.length} priorites',
              ),
              _buildKpiChip(
                icon: Icons.warning_amber,
                label: '$blockedCount blocages',
              ),
              _buildKpiChip(
                icon: Icons.today,
                label: '$dueTodayCount a traiter',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNudgesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              color: Colors.amber,
            ),
            const SizedBox(width: 8),
            Text(
              'A surveiller',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _nudges.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final nudge = _nudges[index];
            final urgency = nudge['urgency'] ?? 'low';
            final urgencyColor = _getUrgencyColor(urgency);

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: urgencyColor.withValues(alpha: 0.1),
                border: Border.all(color: urgencyColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 16,
                        color: urgencyColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nudge['title'] ?? 'Nudge',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            Text(
                              nudge['subtitle'] ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if ((nudge['message'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        nudge['message'],
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _dismissNudge(nudge['id'], reason: 'not_ready'),
                        child: const Text('Ignorer'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => _openContext(nudge['taskId'] ?? ''),
                        child: const Text('Ouvrir'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRemindersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              color: Colors.teal,
            ),
            const SizedBox(width: 8),
            Text(
              'Rappels',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _reminders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final reminder = _reminders[index];
            final severity = reminder['severity'] ?? 'low';
            final color = _getUrgencyColor(severity);
            final options = (reminder['snoozeOptionsMinutes'] as List?)
                    ?.map((e) => int.tryParse('$e') ?? 60)
                    .toList() ??
                [60, 240];

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                border: Border.all(color: color),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder['title'] ?? 'Reminder',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reminder['subtitle'] ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                  ),
                  if ((reminder['message'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        reminder['message'],
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in options)
                        OutlinedButton(
                          onPressed: () => _snoozeReminder(
                            reminder['id'] ?? '',
                            minutes,
                          ),
                          child: Text('Snooze ${_formatMinutes(minutes)}'),
                        ),
                      FilledButton.tonal(
                        onPressed: () => _openContext(reminder['taskId'] ?? ''),
                        child: const Text('View task'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSection(
    String title,
    List<MyDayItem> items,
    Color sectionColor,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: sectionColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: sectionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: sectionColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucun element dans cette section.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _buildTaskCard(items[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(MyDayItem item) {
    final priorityColor = _getPriorityColor(item.priority);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: priorityColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          item.ownerName ?? 'Non assigne',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (item.dueDate != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• Echeance: ${_formatDate(item.dueDate!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                item.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: priorityColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Priorite: ${item.priority}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: priorityColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.whyRanked,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _markTaskDone(item.id),
                icon: const Icon(Icons.done_all, size: 16),
                label: const Text('Fait'),
              ),
              OutlinedButton.icon(
                onPressed: () => _deferTask(item.id),
                icon: const Icon(Icons.schedule, size: 16),
                label: const Text('Reporter'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pingOwner(item.id),
                icon: const Icon(Icons.notifications_active, size: 16),
                label: const Text('Relancer'),
              ),
              IconButton(
                tooltip: 'Ouvrir le contexte',
                onPressed: () => _openContext(item.id),
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.yellow.shade700;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getUrgencyColor(String urgency) {
    switch (urgency) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);

      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        return 'Aujourd hui';
      }

      if (date.year == tomorrow.year &&
          date.month == tomorrow.month &&
          date.day == tomorrow.day) {
        return 'Demain';
      }

      return '${date.month}/${date.day}';
    } catch (e) {
      return '-';
    }
  }

  String _formatMinutes(int minutes) {
    if (minutes >= 60) {
      final hours = (minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1);
      return '${hours}h';
    }
    return '${minutes}m';
  }
}

// Models for API response
class MyDayResponse {
  final bool ok;
  final List<MyDayItem> top3;
  final List<MyDayItem> blocked;
  final List<MyDayItem> dueToday;
  final List<MyDayItem> waitingFor;
  final String requestId;
  final String? computedAt;

  MyDayResponse({
    required this.ok,
    required this.top3,
    required this.blocked,
    required this.dueToday,
    required this.waitingFor,
    required this.requestId,
    this.computedAt,
  });

  factory MyDayResponse.fromJson(Map<String, dynamic> json) {
    return MyDayResponse(
      ok: json['ok'] ?? false,
      top3: (json['top3'] as List?)
              ?.map((item) => MyDayItem.fromJson(item))
              .toList() ??
          [],
      blocked: (json['blocked'] as List?)
              ?.map((item) => MyDayItem.fromJson(item))
              .toList() ??
          [],
      dueToday: (json['dueToday'] as List?)
              ?.map((item) => MyDayItem.fromJson(item))
              .toList() ??
          [],
      waitingFor: (json['waitingFor'] as List?)
              ?.map((item) => MyDayItem.fromJson(item))
              .toList() ??
          [],
      requestId: json['requestId'] ?? 'unknown',
      computedAt: json['computedAt'],
    );
  }
}

class MyDayItem {
  final String id;
  final String title;
  final String description;
  final String priority;
  final String? dueDate;
  final String? ownerName;
  final String whyRanked;

  MyDayItem({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    this.dueDate,
    this.ownerName,
    required this.whyRanked,
  });

  factory MyDayItem.fromJson(Map<String, dynamic> json) {
    return MyDayItem(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      description: json['description'] ?? '',
      priority: json['priority'] ?? 'medium',
      dueDate: json['dueDate'],
      ownerName: json['ownerName'],
      whyRanked: json['whyRanked'] ?? 'Ranked by priority',
    );
  }
}
