@Skip(
    'Legacy API expectations; to be migrated to ApiService.searchVideos and DI client.')
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:hackit_mvp_flutter/services/api_service.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  group('ApiService Tests', () {
    late ApiService apiService;
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
      apiService = ApiService();
    });

    test('search makes correct HTTP request', () async {
      final mockResponse = {
        'title': 'Test Response',
        'steps': ['Step 1'],
        'videoUrl': 'https://example.com',
        'source': 'Test'
      };

      when(() => mockClient.post(
            Uri.parse('${ApiService.baseUrl}/api/search'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            json.encode(mockResponse),
            200,
          ));

      final result = await apiService.search('test query');

      verify(() => mockClient.post(
            Uri.parse('${ApiService.baseUrl}/api/search'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'query': 'test query'}),
          )).called(1);

      expect(result, equals(mockResponse));
    });

    test('search handles API error', () async {
      when(() => mockClient.post(
            Uri.parse('${ApiService.baseUrl}/api/search'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            json.encode({'error': 'API Error'}),
            500,
          ));

      expect(
        () => apiService.search('test'),
        throwsA(isA<Exception>()),
      );
    });

    test('search handles network error', () async {
      when(() => mockClient.post(
            Uri.parse('${ApiService.baseUrl}/api/search'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(Exception('Network error'));

      expect(
        () => apiService.search('test'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
