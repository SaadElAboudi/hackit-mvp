import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/providers/search_provider.dart';
import 'package:hackit_mvp_flutter/services/api_service.dart';
import 'package:hackit_mvp_flutter/models/base_search_result.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class MockApiService extends Mock implements ApiService {}

final baseResult = BaseSearchResult(
  title: 'Test',
  steps: const ['Step 1'],
  videoUrl: 'url',
  source: 'source',
  summary: null,
  metadata: const {},
);

void main() {
  group('SearchProvider Tests', () {
    late SearchProvider provider;
    late MockApiService mockApi;

    setUp(() async {
      mockApi = MockApiService();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      provider = SearchProvider(
          api: mockApi,
          prefs: prefs,
          testMode: true); // testMode disables connectivity streams
    });

    test('initial state is correct', () {
      expect(provider.loading, false);
      expect(provider.error, null);
      expect(provider.result, null);
    });

    test('search with empty query shows error', () async {
      await provider.search('  ');

      expect(provider.error, 'Veuillez entrer une requête');
      expect(provider.loading, false);
      expect(provider.result, null);
    });

    test('successful search updates state correctly', () async {
      when(() => mockApi.searchVideos('test'))
          .thenAnswer((_) async => baseResult);
      await provider.search('test');
      expect(provider.loading, false);
      expect(provider.error, null);
      expect(provider.result?.title, 'Test');
      expect(provider.messages.where((m) => m.role.name == 'assistant').length,
          2); // steps + video
    });

    test('transient failure retries then succeeds', () async {
      int calls = 0;
      when(() => mockApi.searchVideos('test')).thenAnswer((_) async {
        calls++;
        if (calls < 2) {
          throw ApiException('Request timeout');
        }
        return baseResult;
      });
      await provider.search('test');
      expect(calls, greaterThanOrEqualTo(2));
      expect(provider.error, isNull);
      expect(provider.result?.title, 'Test');
    });

    test('non-transient failure does not retry (quota)', () async {
      when(() => mockApi.searchVideos('test'))
          .thenThrow(ApiException('Quota exceeded', statusCode: 429));
      await provider.search('test');
      // Should map to quota message
      expect(provider.error, 'Quota / limite de requêtes atteint.');
    });

    test('reset clears state', () async {
      provider.loading = true;
      provider.error = 'error';
      provider.result = baseResult;
      provider.reset();
      expect(provider.loading, false);
      expect(provider.error, null);
      expect(provider.result, null);
    });

    test('regenerateFor does not add user bubble', () async {
      when(() => mockApi.searchVideos('hello'))
          .thenAnswer((_) async => baseResult);
      await provider.search('hello');
      final userCountBefore =
          provider.messages.where((m) => m.role.name == 'user').length;
      when(() => mockApi.searchVideos('hello'))
          .thenAnswer((_) async => baseResult);
      await provider.regenerateFor('hello');
      final userCountAfter =
          provider.messages.where((m) => m.role.name == 'user').length;
      expect(userCountAfter, userCountBefore); // unchanged
    });

    test('draft set/clear updates state', () {
      provider.setDraft('Bonjour');
      expect(provider.draftText, 'Bonjour');
      provider.clearDraft();
      expect(provider.draftText, isNull);
    });
  });
}
