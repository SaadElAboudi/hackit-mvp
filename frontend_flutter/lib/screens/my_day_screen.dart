import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  MyDayResponse? _myDay;
  bool _isLoading = true;
  String? _errorMessage;
  String? _lastRequestId;
  List<Map<String, dynamic>> _nudges = [];

  @override
  void initState() {
    super.initState();
    _loadMyDay();
    _loadNudges();
  }

  Future<void> _loadMyDay() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prov = context.read<RoomProvider>();
      await prov.ensureCurrentRoom(createIfMissing: false);

      final room = prov.currentRoom;
      if (room == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No room selected. Navigate to Channels first.';
        });
        return;
      }

      final apiService = ApiService(http.Client());
      final responseData = await apiService.getMyDay(room.id);
      final response = MyDayResponse.fromJson(responseData);

      if (!mounted) return;

      setState(() {
        _myDay = response;
        _lastRequestId = response.requestId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load My Day: $e';
      });
    }
  }

  Future<void> _loadNudges() async {
    try {
      final prov = context.read<RoomProvider>();
      final room = prov.currentRoom;
      if (room == null) return;

      final apiService = ApiService(http.Client());
      // Stub: would call apiService.getNudges(room.id)
      // For now, return empty list
      if (!mounted) return;
      setState(() => _nudges = []);
    } catch (e) {
      debugPrint('Error loading nudges: $e');
    }
  }

  Future<void> _dismissNudge(String nudgeId, {String reason = ''}) async {
    try {
      final prov = context.read<RoomProvider>();
      final room = prov.currentRoom;
      if (room == null) return;

      // TODO: call API to dismiss nudge
      setState(() {
        _nudges.removeWhere((n) => n['id'] == nudgeId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nudge dismissed (E1-05 pending)')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _markTaskDone(String taskId) async {
    // E1-04: Action handler stub
    try {
      // TODO: call API to mark task done
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task marked done (E1-04 pending)')),
      );
      await _loadMyDay();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _deferTask(String taskId) async {
    // E1-04: Action handler stub
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task deferred (E1-04 pending)')),
    );
  }

  Future<void> _pingOwner(String taskId) async {
    // E1-04: Action handler stub
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Owner pinged (E1-04 pending)')),
    );
  }

  Future<void> _openContext(String taskId) async {
    // Navigate to task detail screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening context for task $taskId')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Day'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMyDay,
            tooltip: 'Refresh',
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
            onPressed: _loadMyDay,
            child: const Text('Retry'),
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
      return const Center(child: Text('No data available'));
    }

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
                'No tasks today',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Great job! You\'re all caught up.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Generate priorities (E1-02 pending)'),
                    ),
                  );
                },
                child: const Text('Generate Priorities'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyDay,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_nudges.isNotEmpty) ...[
                _buildNudgesSection(),
                const SizedBox(height: 24),
              ],
              _buildSection('Top 3 Priorities', myDay.top3, Colors.blue),
              const SizedBox(height: 24),
              _buildSection('Blockers', myDay.blocked, Colors.red),
              const SizedBox(height: 24),
              _buildSection('Due Today', myDay.dueToday, Colors.orange),
              const SizedBox(height: 24),
              _buildSection('Waiting For', myDay.waitingFor, Colors.purple),
            ],
          ),
        ),
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
              'Nudges',
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
                color: urgencyColor.withOpacity(0.1),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                        child: const Text('Dismiss'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () =>
                            _openContext(nudge['taskId'] ?? ''),
                        child: const Text('View'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              color: sectionColor,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            Text(
              '(${items.length})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No items',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 8),
            itemBuilder: (_, index) => _buildTaskCard(items[index]),
          ),
      ],
    );
  }

  Widget _buildTaskCard(MyDayItem item) {
    final priorityColor = _getPriorityColor(item.priority);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
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
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          item.ownerName ?? 'Unassigned',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (item.dueDate != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• Due: ${_formatDate(item.dueDate!)}',
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
          const SizedBox(height: 12),
          Text(
            item.whyRanked,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildActionButton(
                icon: Icons.done,
                label: 'Done',
                onPressed: () => _markTaskDone(item.id),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.schedule,
                label: 'Defer',
                onPressed: () => _deferTask(item.id),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.notifications_active,
                label: 'Ping',
                onPressed: () => _pingOwner(item.id),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.open_in_new,
                label: 'Open',
                onPressed: () => _openContext(item.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        splashRadius: 16,
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
        return 'Today';
      }

      if (date.year == tomorrow.year &&
          date.month == tomorrow.month &&
          date.day == tomorrow.day) {
        return 'Tomorrow';
      }

      return '${date.month}/${date.day}';
    } catch (e) {
      return 'Unknown';
    }
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
