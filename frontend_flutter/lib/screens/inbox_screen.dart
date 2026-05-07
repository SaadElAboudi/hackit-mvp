import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';
import '../services/api_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final ApiService _api = ApiService.create();
  final TextEditingController _searchController = TextEditingController();
  final List<String> _filters = const [
    'all',
    'mine',
    'team',
    'unassigned',
    'overdue',
  ];
  final Map<String, String> _filterLabels = const {
    'all': 'Tout',
    'mine': 'A moi',
    'team': 'Equipe',
    'unassigned': 'Non assigne',
    'overdue': 'En retard',
  };

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
    _bootstrapInbox();
  }

  @override
  void dispose() {
    _api.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapInbox() async {
    final roomId = await _ensureCurrentRoomId();
    if (roomId == null) return;
    await Future.wait([
      _loadInbox(reset: true, roomId: roomId),
      _loadSlaReport(roomId: roomId),
    ]);
  }

  Future<String?> _ensureCurrentRoomId() async {
    final prov = context.read<RoomProvider>();
    await prov.ensureCurrentRoom(createIfMissing: false);
    final roomId = prov.currentRoom?.id;
    if (roomId != null) return roomId;
    if (!mounted) return null;
    setState(() {
      _isLoading = false;
      _error = 'Aucun salon selectionne';
    });
    return null;
  }

  Future<void> _loadInbox({required bool reset, String? roomId}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final resolvedRoomId = roomId ?? await _ensureCurrentRoomId();
      if (resolvedRoomId == null) return;

      final response = await _api.getInbox(
        resolvedRoomId,
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
        _error = 'Echec du chargement de la boite: $e';
      });
    }
  }

  Future<void> _loadSlaReport({String? roomId}) async {
    try {
      final resolvedRoomId = roomId ?? await _ensureCurrentRoomId();
      if (resolvedRoomId == null) return;
      final report = await _api.getInboxSlaReport(resolvedRoomId);
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
      if (roomId.isEmpty || itemId.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Element introuvable pour le report')),
        );
        return;
      }

      final result = await _api.snoozeInboxItem(
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
            content: Text('Reporte pour $minutes min'),
            duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('Echec du report: $e'), backgroundColor: Colors.red),
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
              'Sante SLA: $health% • $total elements ouverts'
              '${late > 0 ? ' • $late en retard' : ''}',
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

  String _typeLabel(String type) {
    switch (type) {
      case 'task':
        return 'Tache';
      case 'decision':
        return 'Decision';
      case 'message':
      default:
        return 'Message';
    }
  }

  Widget _buildInboxHero() {
    final visibleCount = _items.length;
    final selectedLabel = _filterLabels[_selectedFilter] ?? _selectedFilter;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade700, Colors.cyan.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Queue d execution',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '$visibleCount elements visibles • filtre: $selectedLabel',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
          ),
        ],
      ),
    );
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
                      'Convertir en tache',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Titre *',
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
                    labelText: 'Responsable',
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
                        ? 'Ajouter une echeance (optionnel)'
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
                                    content: Text('Le titre est requis')),
                              );
                              return;
                            }
                            setModalState(() => isSubmitting = true);
                            try {
                              final prov = context.read<RoomProvider>();
                              final roomId = prov.currentRoom?.id ?? '';
                              final itemId = item['itemId']?.toString() ?? '';
                              if (roomId.isEmpty || itemId.isEmpty) {
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Impossible de convertir cet element',
                                    ),
                                  ),
                                );
                                setModalState(() => isSubmitting = false);
                                return;
                              }

                              await _api.convertInboxItem(
                                roomId,
                                itemId,
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
                                    content: Text('Tache creee avec succes')),
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
                                    content: Text('Erreur: $e'),
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
                        : const Text('Creer la tache'),
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
        title: const Text('A traiter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadInbox(reset: true),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildInboxHero(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher une action ou un message...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _loadInbox(reset: true),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                  label: Text(_filterLabels[filter] ?? filter),
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
                                  Center(
                                      child: Text(
                                          'Rien a traiter pour le moment')),
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
                                        child: const Text('Charger plus'),
                                      ),
                                    );
                                  }

                                  final item = _items[index];
                                  final sla =
                                      (item['sla'] ?? 'none').toString();
                                  final color = _slaColor(sla);
                                  final sourceType =
                                      (item['sourceType'] ?? '').toString();
                                  final itemId =
                                      (item['itemId'] ?? '').toString();
                                  final channel =
                                      (item['channel'] ?? '').toString();
                                  final description =
                                      (item['description'] ?? '').toString();

                                  return Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      12,
                                      4,
                                      12,
                                      8,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                          color: Colors.grey.shade200),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.03),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        )
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _typeIcon((item['type'] ?? '')
                                                  .toString()),
                                              color: color,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                (item['title'] ?? '')
                                                    .toString(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: color.withValues(
                                                    alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                sla,
                                                style: TextStyle(
                                                  color: color,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        if (description.trim().isNotEmpty)
                                          Text(
                                            description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: Colors.grey.shade700,
                                                ),
                                          ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                _typeLabel((item['type'] ?? '')
                                                    .toString()),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall,
                                              ),
                                            ),
                                            if (channel.trim().isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: Text(
                                                  '#$channel',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: Colors
                                                            .blue.shade700,
                                                      ),
                                                ),
                                              ),
                                            if (_snoozed.containsKey(itemId))
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: Text(
                                                  'Reporte',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: Colors
                                                            .amber.shade800,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            if (!_snoozed.containsKey(itemId))
                                              PopupMenuButton<int>(
                                                icon: const Icon(
                                                    Icons.snooze_outlined,
                                                    size: 18),
                                                tooltip: 'Reporter',
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 30,
                                                    child: Text('30 min'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 60,
                                                    child: Text('1 heure'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 480,
                                                    child: Text('8 heures'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 1440,
                                                    child: Text('1 jour'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 10080,
                                                    child: Text('1 semaine'),
                                                  ),
                                                ],
                                                onSelected: (minutes) =>
                                                    _snoozeItem(
                                                  context,
                                                  item,
                                                  minutes,
                                                ),
                                              ),
                                            const SizedBox(width: 4),
                                            FilledButton.tonalIcon(
                                              onPressed:
                                                  sourceType == 'workspace_task'
                                                      ? null
                                                      : () => _showConvertModal(
                                                            context,
                                                            item,
                                                          ),
                                              icon: const Icon(Icons.add_task,
                                                  size: 16),
                                              label: const Text('Convertir'),
                                            ),
                                          ],
                                        )
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
