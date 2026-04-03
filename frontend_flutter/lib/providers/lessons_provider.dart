import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../models/lesson.dart';
import '../services/api/api_service.dart';
import '../services/lessons_service.dart';

class LessonsProvider extends ChangeNotifier {
  String _friendlyError(Object e, {String fallback = 'Une erreur est survenue.'}) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;

      if (status == 400) {
        if (data is Map<String, dynamic> && data['error'] is String) {
          return 'Donnees invalides: ${data['error']}';
        }
        return 'Donnees invalides. Verifie les informations de la lecon.';
      }
      if (status == 401) return 'Session expiree. Reconnecte-toi puis reessaie.';
      if (status == 403) return 'Action non autorisee.';
      if (status == 404) return 'Ressource introuvable.';
      if (status == 409) return 'Conflit detecte. Recharge puis reessaie.';
      if (status != null && status >= 500) {
        if (data is Map<String, dynamic> && data['error'] is String) {
          return 'Serveur indisponible: ${data['error']}';
        }
        return 'Serveur indisponible pour le moment. Reessaie dans quelques secondes.';
      }

      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Le serveur met trop de temps a repondre. Reessaie.';
        case DioExceptionType.connectionError:
          return 'Impossible de joindre le serveur. Verifie ta connexion.';
        case DioExceptionType.cancel:
          return 'Requete annulee.';
        case DioExceptionType.badCertificate:
          return 'Probleme de certificat SSL.';
        case DioExceptionType.badResponse:
        case DioExceptionType.unknown:
          break;
      }
    }
    return fallback;
  }

  Future<void> deleteLesson(String lessonId) async {
    final idx = lessons.indexWhere((l) => l.id == lessonId);
    if (idx == -1) return;
    // Only send delete to backend if lessonId is a valid ObjectId
    final isObjectId = RegExp(r'^[a-fA-F0-9]{24}\$').hasMatch(lessonId);
    try {
      if (isObjectId) {
        await _service.deleteLesson(lessonId: lessonId);
      }
      lessons.removeAt(idx);
      notifyListeners();
    } catch (e) {
      error = _friendlyError(e, fallback: 'Impossible de supprimer la lecon.');
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
      lessons = await _service.listLessons();
      suggestedActions = null;
      error = null;
    } catch (e) {
      error = _friendlyError(e, fallback: 'Impossible de charger les livrables.');
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
      error = _friendlyError(e, fallback: 'Impossible de generer la lecon.');
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
      error = _friendlyError(e, fallback: 'Impossible d\'enregistrer la lecon.');
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
    final newFav = !current.favorite;
    final isObjectId = RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(lessonId);
    try {
      if (isObjectId) {
        final updated =
            await _service.setFavorite(lessonId: lessonId, favorite: newFav);
        lessons[idx] = updated;
      } else {
        lessons[idx] = Lesson(
          id: current.id,
          userId: current.userId,
          title: current.title,
          summary: current.summary,
          steps: current.steps,
          videoUrl: current.videoUrl,
          favorite: newFav,
          views: current.views,
          lastViewedAt: current.lastViewedAt,
          createdAt: current.createdAt,
          progress: current.progress,
          reminder: current.reminder,
          guestPrompt: current.guestPrompt,
        );
      }
      notifyListeners();
    } catch (e) {
      error = _friendlyError(e, fallback: 'Impossible de mettre a jour le favori.');
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
