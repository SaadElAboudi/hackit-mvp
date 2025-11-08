import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/providers/search_provider.dart';
import 'package:hackit_mvp_flutter/services/api_service.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  group('SearchProvider Tests', () {
    late SearchProvider provider;
    late MockApiService mockApi;

    setUp(() {
      mockApi = MockApiService();
      provider = SearchProvider();
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
      final mockResponse = {
        'title': 'Test',
        'steps': ['Step 1'],
        'videoUrl': 'url',
        'source': 'source'
      };

      when(() => mockApi.search('test'))
          .thenAnswer((_) async => mockResponse);

      await provider.search('test');

      expect(provider.loading, false);
      expect(provider.error, null);
      expect(provider.result?.title, 'Test');
    });

    test('failed search shows error', () async {
      when(() => mockApi.search('test'))
          .thenThrow(Exception('API Error'));

      await provider.search('test');

      expect(provider.loading, false);
      expect(provider.error, isNotNull);
      expect(provider.result, null);
    });

    test('reset clears state', () async {
      provider.loading = true;
      provider.error = 'error';
      provider.result = SearchResult(
        title: 'test',
        steps: [],
        videoUrl: '',
        source: ''
      );

      provider.reset();

      expect(provider.loading, false);
      expect(provider.error, null);
      expect(provider.result, null);
    });
  });
}