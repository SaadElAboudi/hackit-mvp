import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/models/search_result.dart';

void main() {
  test('SearchResult.fromMap parses valid map', () {
    final map = {
      'title': 'How to tie a tie',
      'steps': ['Start with the wide end', 'Cross over', 'Loop through'],
      'videoUrl': 'https://youtu.be/example',
      'source': 'YouTube'
    };

    final res = SearchResult.fromMap(map);

    expect(res.title, 'How to tie a tie');
    expect(res.steps.length, 3);
    expect(res.videoUrl, 'https://youtu.be/example');
    expect(res.source, 'YouTube');
  });
}
