import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson.dart';
import '../services/api/api_service.dart';
import '../services/lessons_service.dart';

class LessonsProvider extends ChangeNotifier {
  final LessonsService _service;

  LessonsProvider({required SharedPreferences prefs, ApiService? api})
      : _service =
            LessonsService(api: api ?? ApiService.create(), prefs: prefs);

  List<Lesson> _lessons = [];
  bool _loading = false;
  String? _error;
  bool _initialized = false;

  List<Lesson> get lessons => _lessons;
  bool get loading => _loading;
  String? get error => _error;
  String get userId => _service.userId;
  bool get initialized => _initialized;

  Future<void> initIfNeeded() async {
    if (_initialized) return;
    await refresh();
    _initialized = true;
  }

  Future<void> refresh({bool? favorite}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _lessons = await _service.listLessons(favorite: favorite);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Lesson?> generateAndAdd(
      {required String query, bool useGemini = true}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final lesson =
          await _service.generateLesson(query: query, useGemini: useGemini);
      _lessons = [lesson, ..._lessons];
      return lesson;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Lesson?> saveFromChat({
    required String title,
    required List<String> steps,
    required String videoUrl,
    String? summary,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final lesson = await _service.createLessonFromChat(
        title: title,
        steps: steps,
        videoUrl: videoUrl,
        summary: summary,
      );
      _lessons = [lesson, ..._lessons];
      return lesson;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(String lessonId) async {
    final idx = _lessons.indexWhere((l) => l.id == lessonId);
    if (idx == -1) return;
    final current = _lessons[idx];
    try {
      final updated = await _service.setFavorite(
          lessonId: lessonId, favorite: !current.favorite);
      _lessons[idx] = updated;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> recordView(String lessonId) async {
    final idx = _lessons.indexWhere((l) => l.id == lessonId);
    try {
      final updated = await _service.recordView(lessonId: lessonId);
      if (idx != -1) {
        _lessons[idx] = updated;
      }
      notifyListeners();
    } catch (_) {
      // Swallow, non-critical.
    }
  }
}
