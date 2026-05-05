import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';
import '../services/api_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _filters = const [
    'all',
    'mine',
    'team',
    'unassigned',
    'overdue',
  ];

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _error;
  String _selectedFilter = 'all';
  String? _nextCursor;
  Map<String, dynamic>? _slaReport;
  // itemId -> snoozeUntil ISO
  final Map<String, String> _snoozed = {};

  @override
  void initState() {
    super.initState();
    _loadInbox(reset: true);
    _loadSlaReport();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInbox({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final prov = context.read<RoomProvider>();
      await prov.ensureCurrentRoom(createIfMissing: false);
      final room = prov.currentRoom;
      if (room == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'No room selected';
        });
        return;
      }

      final api = ApiService(http.Client());
      final response = await api.getInbox(
        room.id,
        filter: _selectedFilter == 'all' ? null : _selectedFilter,
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        before: reset ? null : _nextCursor,
      );

      final fetched = (response['items'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _items = reset ? fetched : [..._items, ...fetched];
        _nextCursor = response['nextCursor'] as String?;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load inbox: $e';
      });
    }
  }

  Future<void> _loadSlaReport() async {
    try {
      final prov = context.read<RoomProvider>();
      await prov.ensureCurrentRoom(createIfMissing: false);
      final room = prov.currentRoom;
      if (room == null) return;
      final api = ApiService(http.Client());
      final report = await api.getInboxSlaReport(room.id);
      if (!mounted) return;
      setState(() => _slaReport = report);
    } catch (_) {
      // non-critical, ignore
    }
  }

  Future<void> _snoozeItem(
      BuildContext context, Map<String, dynamic> item, int minutes) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final prov = context.read<RoomProvider>();
      final roomId = prov.currentRoom?.id ?? '';
      final itemId = (item['itemId'] ?? '').toString();
      final api = ApiService(http.Client());
      final result = await api.snoozeInboxItem(
        roomId,
        itemId,
        snoozeMinutes: minutes,
        sourceType: (item['sourceType'] ?? 'unknown').toString(),
      );
      if (!mounted) return;
      final until = result['snoozeUntil']?.toString() ?? '';
      setState(() => _snoozed[itemId] = until);
      messenger.showSnackBar(
        SnackBar(
            content: Text('Snoozed for $minutes min'),
            duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('Snooze failed: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildSlaBar() {
    final report = _slaReport;
    if (report == null) return const SizedBox.shrink();
    final health = (report['healthScore'] as num?)?.toInt() ?? 100;
    final buckets = (report['buckets'] as Map?) ?? {};
    final late = (buckets['late'] as num?)?.toInt() ?? 0;
    final total = (report['total'] as num?)?.toInt() ?? 0;
    final barColor = health >= 80
        ? Colors.green
        : health >= 50
            ? Colors.orange
            : Colors.red;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.08),
        border: Border.all(color: barColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.health_and_safety, size: 16, color: barColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'SLA health: $health% • $total open items'
              '${late > 0 ? ' • $late late' : ''}',
              style: TextStyle(fontSize: 12, color: barColor),
            ),
          ),
        ],
      ),
    );
  }

  Color _slaColor(String sla) {
    switch (sla) {
      case 'late':
        return Colors.red;
      case 'today':
        return Colors.orange;
      case 'tomorrow':
      case 'soon':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'task':
        return Icons.task_alt;
      case 'decision':
        return Icons.gavel;
      case 'message':
      default:
        return Icons.forum;
    }
  }

  Future<void> _showConvertModal(
      BuildContext context, Map<String, dynamic> item) async {
    final titleCtrl =
        TextEditingController(text: (item['title'] ?? '').toString());
    final descCtrl =
        TextEditingController(text: (item['description'] ?? '').toString());
    final ownerCtrl =
        TextEditingController(text: (item['ownerName'] ?? '').toString());
    DateTime? pickedDate;
    final rawDue = item['dueDate'];
    if (rawDue != null && rawDue.toString().isNotEmpty) {
      pickedDate = DateTime.tryParse(rawDue.toString());
    }
    final dateNotifier = ValueNotifier<DateTime?>(pickedDate);
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.task_alt, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Convert to Task',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ownerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Owner name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<DateTime?>(
                  valueListenable: dateNotifier,
                  builder: (_, date, __) => OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(date == null
                        ? 'Set due date (optional)'
                        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 2)),
                      );
                      if (picked != null) {
                        dateNotifier.value = picked;
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text('Title is required')),
                              );
                              return;
                            }
                            setModalState(() => isSubmitting = true);
                            try {
                              final prov = context.read<RoomProvider>();
                              final roomId = prov.currentRoom?.id ?? '';
                              final api = ApiService(http.Client());
                              await api.convertInboxItem(
                                roomId,
                                item['itemId'].toString(),
                                sourceType:
                                    (item['sourceType'] ?? 'room_message')
                                        .toString(),
                                title: title,
                                description: descCtrl.text.trim(),
                                ownerName: ownerCtrl.text.trim(),
                                dueDate: dateNotifier.value?.toIso8601String(),
                              );
                              if (!context.mounted) return;
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Task created successfully')),
                              );
                              // Remove the item from local list if it was a
                              // message/decision (task is already there)
                              final src = (item['sourceType'] ?? '').toString();
                              if (src != 'workspace_task') {
                                setState(() {
                                  _items.removeWhere(
                                      (i) => i['itemId'] == item['itemId']);
                                });
                              }
                            } catch (e) {
                              setModalState(() => isSubmitting = false);
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Task'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );

    titleCtrl.dispose();
    descCtrl.dispose();
    ownerCtrl.dispose();
    dateNotifier.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadInbox(reset: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search inbox...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _loadInbox(reset: true),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _loadInbox(reset: true),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, index) {
                final filter = _filters[index];
                return ChoiceChip(
                  label: Text(filter),
                  selected: _selectedFilter == filter,
                  onSelected: (_) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                    _loadInbox(reset: true);
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _filters.length,
            ),
          ),
          const SizedBox(height: 8),
          _buildSlaBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : RefreshIndicator(
                        onRefresh: () => _loadInbox(reset: true),
                        child: _items.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 120),
                                  Center(child: Text('Inbox is empty')),
                                ],
                              )
                            : ListView.builder(
                                itemCount: _items.length + 1,
                                itemBuilder: (_, index) {
                                  if (index == _items.length) {
                                    if (_nextCursor == null) {
                                      return const SizedBox(height: 24);
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            _loadInbox(reset: false),
                                        child: const Text('Load more'),
                                      ),
                                    );
                                  }

                                  final item = _items[index];
                                  final sla =
                                      (item['sla'] ?? 'none').toString();
                                  final color = _slaColor(sla);

                                  return ListTile(
                                    leading: Icon(
                                      _typeIcon(
                                          (item['type'] ?? '').toString()),
                                      color: color,
                                    ),
                                    title:
                                        Text((item['title'] ?? '').toString()),
                                    subtitle: Text(
                                      [
                                        (item['description'] ?? '').toString(),
                                        if ((item['channel'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          '#${item['channel']}'
                                      ]
                                          .where((e) => e.trim().isNotEmpty)
                                          .join(' • '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                color.withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            sla,
                                            style: TextStyle(color: color),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        if (_snoozed.containsKey(
                                            (item['itemId'] ?? '').toString()))
                                          const Tooltip(
                                            message: 'Snoozed',
                                            child: Icon(Icons.snooze,
                                                size: 16,
                                                color: Colors.grey),
                                          )
                                        else
                                          PopupMenuButton<int>(
                                            icon: const Icon(
                                                Icons.snooze_outlined,
                                                size: 18),
                                            tooltip: 'Snooze',
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 30,
                                                  child: Text('30 min')),
                                              PopupMenuItem(
                                                  value: 60,
                                                  child: Text('1 hour')),
                                              PopupMenuItem(
                                                  value: 480,
                                                  child: Text('8 hours')),
                                              PopupMenuItem(
                                                  value: 1440,
                                                  child: Text('1 day')),
                                              PopupMenuItem(
                                                  value: 10080,
                                                  child: Text('1 week')),
                                            ],
                                            onSelected: (minutes) =>
                                                _snoozeItem(
                                                    context, item, minutes),
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.add_task,
                                              size: 20),
                                          tooltip: 'Convert to task',
                                          onPressed: () =>
                                              _showConvertModal(context, item),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
