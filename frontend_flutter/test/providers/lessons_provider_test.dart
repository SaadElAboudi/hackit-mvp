import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'package:hackit_mvp_flutter/providers/lessons_provider.dart';
import 'package:hackit_mvp_flutter/services/api/api_service.dart';

class FakeApiService extends ApiService {
  FakeApiService() : super(Dio());

  // In-memory store of lessons
  final List<Map<String, dynamic>> _store = [
    {
      'id': 'l1',
      'userId': 'u_1',
      'title': 'Intro Dart',
      'summary': 'Résumé',
      'steps': ['Étape 1', 'Étape 2'],
      'videoUrl': 'https://youtu.be/vid1',
      'favorite': false,
      'views': 0,
      'createdAt': DateTime.now().toIso8601String(),
    },
    {
      'id': 'l2',
      'userId': 'u_1',
      'title': 'Flutter Layout',
      'summary': 'Résumé',
      'steps': ['Row', 'Column'],
      'videoUrl': 'https://youtu.be/vid2',
      'favorite': true,
      'views': 3,
      'createdAt': DateTime.now().toIso8601String(),
    },
  ];

  Response _resp(data, {String path = '/'}) => Response(
      requestOptions: RequestOptions(path: path), data: data, statusCode: 200);

  @override
  Future<Response> listLessons(
      {required String userId,
      bool? favorite,
      String sort = 'createdAt',
      String order = 'desc',
      int limit = 50,
      int offset = 0}) async {
    var items = _store.where((e) => e['userId'] == userId).toList();
    if (favorite != null) {
      items = items.where((e) => e['favorite'] == favorite).toList();
    }
    return _resp(items, path: '/api/lessons');
  }

  @override
  Future<Response> generateLesson(
      {required String query,
      required String userId,
      bool useGemini = true}) async {
    final m = {
      'id': 'gen_${_store.length + 1}',
      'userId': userId,
      'title': 'Leçon: $query',
      'summary': 'Résumé pour $query',
      'steps': ['Définir', 'Expliquer', 'Conclure'],
      'videoUrl': 'https://youtu.be/new${_store.length + 1}',
      'favorite': false,
      'views': 0,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _store.insert(0, m);
    return _resp(m, path: '/api/generateLesson');
  }

  @override
  Future<Response> setFavorite(
      {required String lessonId, required bool favorite}) async {
    final idx = _store.indexWhere((e) => e['id'] == lessonId);
    if (idx != -1) {
      _store[idx]['favorite'] = favorite;
    }
    return _resp(_store[idx], path: '/api/lessons/$lessonId/favorite');
  }

  @override
  Future<Response> recordView({required String lessonId}) async {
    final idx = _store.indexWhere((e) => e['id'] == lessonId);
    if (idx != -1) {
      _store[idx]['views'] = (_store[idx]['views'] as int) + 1;
    }
    return _resp(_store[idx], path: '/api/lessons/$lessonId/view');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LessonsProvider', () {
    late SharedPreferences prefs;
    late FakeApiService api;
    late LessonsProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      // Ensure the generated/stored userId matches the FakeApiService seed
      await prefs.setString('hackit:v1:userId', 'u_1');
      api = FakeApiService();
      provider = LessonsProvider(prefs: prefs, api: api);
    });

    test('initial refresh loads lessons', () async {
      expect(provider.lessons.length, 0);
      await provider.initIfNeeded();
      expect(provider.initialized, true);
      expect(provider.lessons.length, 2);
      expect(provider.lessons.first.title, 'Intro Dart');
    });

    test('generateAndAdd prepends new lesson', () async {
      await provider.initIfNeeded();
      final before = provider.lessons.length;
      final lesson = await provider.generateAndAdd(query: 'Streams');
      expect(lesson, isNotNull);
      expect(provider.lessons.length, before + 1);
      expect(provider.lessons.first.title, startsWith('Leçon: Streams'));
    });

    test('toggleFavorite flips favorite flag', () async {
      await provider.initIfNeeded();
      final target = provider.lessons.first;
      final initialFav = target.favorite;
      await provider.toggleFavorite(target.id);
      final updated = provider.lessons.first;
      expect(updated.favorite, isNot(initialFav));
    });

    test('recordView increments views', () async {
      await provider.initIfNeeded();
      final target = provider.lessons.last; // second seeded
      final initialViews = target.views;
      await provider.recordView(target.id);
      final updated = provider.lessons.last;
      expect(updated.views, initialViews + 1);
    });
  });
}
