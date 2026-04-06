import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/action_task.dart';

const _kTasksKey = 'action_tasks';

class ActionTaskProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  List<ActionTask> _tasks = [];

  ActionTaskProvider(this._prefs) {
    _load();
  }

  List<ActionTask> get tasks => List.unmodifiable(_tasks);
  int get pendingCount => _tasks.where((t) => !t.done).length;

  void _load() {
    final raw = _prefs.getString(_kTasksKey);
    if (raw != null && raw.isNotEmpty) {
      _tasks = ActionTask.decodeList(raw);
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_kTasksKey, ActionTask.encodeList(_tasks));
  }

  /// Parse actions from a deliveryPlan + raw steps and add them as new tasks.
  /// Deduplicates by title to avoid re-adding the same plan.
  Future<void> importFromPlan({
    required String title,
    required Map<String, dynamic>? deliveryPlan,
    required List<String> steps,
  }) async {
    final existingTitles = _tasks.map((t) => t.title).toSet();

    List<String> candidates = [];

    // Prefer structured nextActions from deliveryPlan
    if (deliveryPlan != null) {
      final na = deliveryPlan['nextActions'];
      if (na is List && na.isNotEmpty) {
        candidates = na.map((e) => e.toString()).toList();
      }
    }

    // Fallback to steps if nothing structured
    if (candidates.isEmpty) {
      candidates = steps.where((s) => s.trim().isNotEmpty).toList();
    }

    final toAdd = candidates
        .where((c) => c.trim().isNotEmpty && !existingTitles.contains(c.trim()))
        .map((c) => ActionTask(
              id: const Uuid().v4(),
              title: c.trim(),
              priority: ActionTask.inferPriority(c),
            ))
        .toList();

    if (toAdd.isEmpty) return;
    _tasks = [..._tasks, ...toAdd];
    await _save();
    notifyListeners();
  }

  Future<void> toggleDone(String id) async {
    _tasks = _tasks
        .map((t) => t.id == id ? t.copyWith(done: !t.done) : t)
        .toList();
    await _save();
    notifyListeners();
  }

  Future<void> updateOwner(String id, String owner) async {
    _tasks = _tasks
        .map((t) => t.id == id ? t.copyWith(owner: owner) : t)
        .toList();
    await _save();
    notifyListeners();
  }

  Future<void> updateDueDate(String id, String dueDate) async {
    _tasks = _tasks
        .map((t) => t.id == id ? t.copyWith(dueDate: dueDate) : t)
        .toList();
    await _save();
    notifyListeners();
  }

  Future<void> updatePriority(String id, TaskPriority priority) async {
    _tasks = _tasks
        .map((t) => t.id == id ? t.copyWith(priority: priority) : t)
        .toList();
    await _save();
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    _tasks = _tasks.where((t) => t.id != id).toList();
    await _save();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _tasks = [];
    await _save();
    notifyListeners();
  }

  /// Returns CSV string of all tasks.
  String toCsv() {
    const header = 'Priorité,Titre,Propriétaire,Échéance,Statut';
    final rows = _tasks.map((t) {
      String escape(String? s) {
        if (s == null || s.isEmpty) return '';
        if (s.contains(',') || s.contains('"') || s.contains('\n')) {
          return '"${s.replaceAll('"', '""')}"';
        }
        return s;
      }

      return [
        escape(t.priorityLabel),
        escape(t.title),
        escape(t.owner),
        escape(t.dueDate),
        escape(t.done ? 'Fait' : 'À faire'),
      ].join(',');
    }).join('\n');
    return '$header\n$rows';
  }
}
