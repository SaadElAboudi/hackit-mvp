import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/models/room.dart';

void main() {
  group('DomainTemplate model', () {
    test('fromJson parses starterPrompts and versionWeights', () {
      final template = DomainTemplate.fromJson({
        'id': 'marketing',
        'version': 'v1',
        'versionWeights': {'v1': 80, 'v2': 20},
        'name': 'Marketing',
        'emoji': '📣',
        'description': 'Desc',
        'purpose': 'Purpose',
        'starterPrompts': [
          'Plan 30 jours',
          'Messaging framework',
        ],
      });

      expect(template.id, 'marketing');
      expect(template.versionWeights['v1'], 80);
      expect(template.versionWeights['v2'], 20);
      expect(template.starterPrompts.length, 2);
      expect(template.starterPrompts.first, 'Plan 30 jours');
    });

    test('fromJson handles missing starterPrompts', () {
      final template = DomainTemplate.fromJson({
        'id': 'ops',
        'name': 'Ops',
      });

      expect(template.id, 'ops');
      expect(template.starterPrompts, isEmpty);
    });
  });
}
