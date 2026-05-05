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

  @override
  void initState() {
    super.initState();
    _loadInbox(reset: true);
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
                                        onPressed: () => _loadInbox(reset: false),
                                        child: const Text('Load more'),
                                      ),
                                    );
                                  }

                                  final item = _items[index];
                                  final sla = (item['sla'] ?? 'none').toString();
                                  final color = _slaColor(sla);

                                  return ListTile(
                                    leading: Icon(
                                      _typeIcon((item['type'] ?? '').toString()),
                                      color: color,
                                    ),
                                    title: Text((item['title'] ?? '').toString()),
                                    subtitle: Text(
                                      [
                                        (item['description'] ?? '').toString(),
                                        if ((item['channel'] ?? '').toString().isNotEmpty)
                                          '#${item['channel']}'
                                      ].where((e) => e.trim().isNotEmpty).join(' • '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        sla,
                                        style: TextStyle(color: color),
                                      ),
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
