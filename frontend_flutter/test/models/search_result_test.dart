import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/models/search_result.dart';

void main() {
  group('SearchResult Model Tests', () {
    test('fromMap creates valid object with complete data', () {
      final map = {
        'title': 'Test Title',
        'steps': ['Step 1', 'Step 2'],
        'videoUrl': 'https://example.com',
        'source': 'Test Source'
      };

      final result = SearchResult.fromMap(map);

      expect(result.title, 'Test Title');
      expect(result.steps, ['Step 1', 'Step 2']);
      expect(result.videoUrl, 'https://example.com');
      expect(result.source, 'Test Source');
    });

    test('fromMap handles missing data gracefully', () {
      final map = {'title': 'Only Title'};
      
      final result = SearchResult.fromMap(map);
      
      expect(result.title, 'Only Title');
      expect(result.steps, isEmpty);
      expect(result.videoUrl, '');
      expect(result.source, '');
    });

    test('fromMap handles null values', () {
      final map = {
        'title': null,
        'steps': null,
        'videoUrl': null,
        'source': null
      };
      
      final result = SearchResult.fromMap(map);
      
      expect(result.title, '');
      expect(result.steps, isEmpty);
      expect(result.videoUrl, '');
      expect(result.source, '');
    });

    test('toMap converts object correctly', () {
      const result = SearchResult(
        title: 'Test',
        steps: ['1', '2'],
        videoUrl: 'url',
        source: 'source'
      );
      
      final map = result.toMap();
      
      expect(map['title'], 'Test');
      expect(map['steps'], ['1', '2']);
      expect(map['videoUrl'], 'url');
      expect(map['source'], 'source');
    });
  });
}