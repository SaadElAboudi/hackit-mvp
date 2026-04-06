import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a user's feedback on a plan.
class PlanFeedback {
  final String rating; // 'pertinent' | 'moyen' | 'hors-sujet'
  final String? reason;
  final DateTime savedAt;

  PlanFeedback({
    required this.rating,
    this.reason,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'reason': reason,
        'savedAt': savedAt.toIso8601String(),
      };

  factory PlanFeedback.fromJson(Map<String, dynamic> j) => PlanFeedback(
        rating: j['rating'] as String,
        reason: j['reason'] as String?,
        savedAt: DateTime.parse(j['savedAt'] as String),
      );
}

/// Persists and retrieves user feedback on plans, keyed by query+mode.
class PlanFeedbackProvider extends ChangeNotifier {
  static const _key = 'plan_feedbacks';

  final SharedPreferences _prefs;
  final Map<String, PlanFeedback> _feedbacks = {};

  PlanFeedbackProvider(this._prefs) {
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          _feedbacks[entry.key] = PlanFeedback.fromJson(
              Map<String, dynamic>.from(entry.value as Map));
        }
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(
      _feedbacks.map((k, v) => MapEntry(k, v.toJson())),
    );
    await _prefs.setString(_key, encoded);
  }

  String _makeKey(String query, String mode) =>
      '${query.trim().toLowerCase()}|$mode';

  PlanFeedback? getFeedback(String query, String mode) =>
      _feedbacks[_makeKey(query, mode)];

  Future<void> saveFeedback(
    String query,
    String mode,
    String rating, {
    String? reason,
  }) async {
    _feedbacks[_makeKey(query, mode)] = PlanFeedback(
      rating: rating,
      reason: reason?.trim().isEmpty == true ? null : reason?.trim(),
      savedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> deleteFeedback(String query, String mode) async {
    _feedbacks.remove(_makeKey(query, mode));
    await _persist();
    notifyListeners();
  }

  int get totalFeedbacks => _feedbacks.length;

  /// Simple summary for observability: count by rating.
  Map<String, int> get ratingSummary {
    final counts = <String, int>{};
    for (final f in _feedbacks.values) {
      counts[f.rating] = (counts[f.rating] ?? 0) + 1;
    }
    return counts;
  }
}
