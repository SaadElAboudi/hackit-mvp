import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../models/lesson.dart';
import 'api/api_service.dart';

/// Service wrapper around lesson persistence endpoints.
class LessonsService {
  Future<void> deleteLesson({required String lessonId}) async {
    await _api.deleteLesson(lessonId: lessonId);
  }

  /// Static method for provider: returns items, total, suggestedActions from API response
  static Future<Map<String, dynamic>> getLessons() async {
    final api = ApiService.create();
    final resp = await api.get('/api/lessons');
    final data = resp.data as Map<String, dynamic>?;
    return {
      'items': data?['items'] ?? [],
      'total': data?['total'] ?? 0,
      'suggestedActions': data?['suggestedActions'],
    };
  }

  static const _userIdKey = 'hackit:v1:userId';

  final ApiService _api;
  ApiService get api => _api;
  final SharedPreferences _prefs;

  LessonsService({required ApiService api, required SharedPreferences prefs})
      : _api = api,
        _prefs = prefs;

  /// Returns a stable per-device userId persisted in SharedPreferences.
  String get userId {
    final existing = _prefs.getString(_userIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generateUserId();
    _prefs.setString(_userIdKey, id);
    return id;
  }

  String _generateUserId() {
    final rnd = Random();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final salt = List.generate(6, (_) => rnd.nextInt(36))
        .map((n) => n.toRadixString(36))
        .join();
    return 'u_${ts}_$salt';
  }

  Future<Lesson> generateLesson(
      {required String query, bool useGemini = true}) async {
    final Response resp = await _api.generateLesson(
      query: query,
      userId: userId,
      useGemini: useGemini,
    );
    return Lesson.fromMap(resp.data as Map<String, dynamic>,
        userIdFallback: userId);
  }

  /// Create a lesson directly from chat-rendered content.
  Future<Lesson> createLessonFromChat({
    required String title,
    required List<String> steps,
    required String videoUrl,
    String? summary,
  }) async {
    final Response resp = await _api.createLesson(
      userId: userId,
      title: title,
      steps: steps,
      videoUrl: videoUrl,
      summary: summary,
    );
    return Lesson.fromMap(resp.data as Map<String, dynamic>,
        userIdFallback: userId);
  }

  Future<List<Lesson>> listLessons(
      {bool? favorite,
      String sort = 'createdAt',
      String order = 'desc',
      int limit = 50,
      int offset = 0}) async {
    final Response resp = await _api.listLessons(
      userId: userId,
      favorite: favorite,
      sort: sort,
      order: order,
      limit: limit,
      offset: offset,
    );
    final data = resp.data;
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map((m) => Lesson.fromMap(m, userIdFallback: userId))
          .toList();
    }
    // Support { items: [] }
    final items = (data as Map<String, dynamic>?)?['items'];
    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map((m) => Lesson.fromMap(m, userIdFallback: userId))
          .toList();
    }
    return [];
  }

  Future<Lesson> setFavorite(
      {required String lessonId, required bool favorite}) async {
    final Response resp =
        await _api.setFavorite(lessonId: lessonId, favorite: favorite);
    return Lesson.fromMap(resp.data as Map<String, dynamic>,
        userIdFallback: userId);
  }

  Future<Lesson> recordView({required String lessonId}) async {
    final Response resp = await _api.recordView(lessonId: lessonId);
    return Lesson.fromMap(resp.data as Map<String, dynamic>,
        userIdFallback: userId);
  }
}
