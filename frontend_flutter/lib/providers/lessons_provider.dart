  Future<void> deleteLesson(String lessonId) async {
    final idx = lessons.indexWhere((l) => l.id == lessonId);
    if (idx == -1) return;
    try {
      await _service.deleteLesson(lessonId: lessonId);
      lessons.removeAt(idx);
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson.dart';
import '../services/api/api_service.dart';
import '../services/lessons_service.dart';

class LessonsProvider extends ChangeNotifier {
    Future<void> deleteLesson(String lessonId) async {
      final idx = lessons.indexWhere((l) => l.id == lessonId);
      if (idx == -1) return;
      try {
        await _service.deleteLesson(lessonId: lessonId);
        lessons.removeAt(idx);
        notifyListeners();
      } catch (e) {
        error = e.toString();
        notifyListeners();
      }
    }
  bool _initialized = false;

  /// Initializes lessons if not already loaded
  Future<void> initIfNeeded() async {
    if (_initialized || lessons.isNotEmpty) return;
    await fetchLessons();
    _initialized = true;
  }

  final LessonsService _service;
  LessonsService get service => _service;

  LessonsProvider({required SharedPreferences prefs, ApiService? api})
      : _service =
            LessonsService(api: api ?? ApiService.create(), prefs: prefs);

  List<Lesson> lessons = [];
  String? error;
  bool loading = false;
  List<Map<String, dynamic>>? suggestedActions;

  Future<void> fetchLessons({bool force = false}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final resp = await LessonsService.getLessons();
      lessons = (resp['items'] as List<dynamic>?)
              ?.map<Lesson>((j) => Lesson.fromMap(j as Map<String, dynamic>))
              .toList() ??
          [];
      suggestedActions = resp['suggestedActions'] != null
          ? List<Map<String, dynamic>>.from(resp['suggestedActions'])
          : null;
      error = null;
    } catch (e) {
      error = e.toString();
      lessons = [];
      suggestedActions = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Lesson?> generateAndAdd(
      {required String query, bool useGemini = true}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final lesson =
          await _service.generateLesson(query: query, useGemini: useGemini);
      lessons = [lesson, ...lessons];
      return lesson;
    } catch (e) {
      error = e.toString();
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Lesson?> saveFromChat({
    required String title,
    required List<String> steps,
    required String videoUrl,
    String? summary,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final lesson = await _service.createLessonFromChat(
        title: title,
        steps: steps,
        videoUrl: videoUrl,
        summary: summary,
      );
      lessons = [lesson, ...lessons];
      return lesson;
    } catch (e) {
      error = e.toString();
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(String lessonId) async {
    final idx = lessons.indexWhere((l) => l.id == lessonId);
    if (idx == -1) return;
    final current = lessons[idx];
    try {
      final updated = await _service.setFavorite(
          lessonId: lessonId, favorite: !current.favorite);
      lessons[idx] = updated;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> recordView(String lessonId) async {
    final idx = lessons.indexWhere((l) => l.id == lessonId);
    try {
      final updated = await _service.recordView(lessonId: lessonId);
      if (idx != -1) {
        lessons[idx] = updated;
      }
      notifyListeners();
    } catch (_) {
      // Swallow, non-critical.
    }
  }
}
