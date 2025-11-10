import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackit_mvp_flutter/widgets/chapters_view.dart';
import 'package:hackit_mvp_flutter/models/base_search_result.dart';
import 'package:hackit_mvp_flutter/services/video_seek_service.dart';

void main() {
  group('ChaptersView', () {
    late List<Duration> seeks;

    setUp(() {
      seeks = [];
      // Register a fake player so seekOrQueue triggers immediately.
      VideoSeekService.instance
          .register((d) => seeks.add(d), baseUrl: 'https://youtu.be/xyz');
    });

    tearDown(() {
      VideoSeekService.instance.unregister();
    });

    Widget _wrap(Widget child) => MaterialApp(
          home: Scaffold(body: child),
        );

    Chapter _ch(int s, String title) =>
        Chapter(index: 0, title: title, startSec: s);

    testWidgets('tapping a chapter seeks and shows snackbar', (tester) async {
      final chapters = <Chapter>[
        _ch(5, 'Intro'),
        _ch(65, 'Partie 1'),
      ];

      await tester.pumpWidget(_wrap(
          ChaptersView(chapters: chapters, videoUrl: 'https://youtu.be/xyz')));

      // Expand tile
      expect(find.textContaining('Chapitres'), findsOneWidget);
      await tester.tap(find.textContaining('Chapitres'));
      await tester.pumpAndSettle();

      // Tap first chapter
      await tester.tap(find.text('Intro'));
      await tester.pump();

      expect(seeks, isNotEmpty);
      expect(seeks.first.inSeconds, 5);
      // Snackbar appears
      expect(find.byType(SnackBar), findsOneWidget);
      // Allow debounce timer to elapse to avoid pending timer assertion.
      await tester.pump(const Duration(milliseconds: 410));
    });

    testWidgets('debounces rapid taps within 400ms', (tester) async {
      final chapters = <Chapter>[
        _ch(10, 'Ch 1'),
      ];
      await tester.pumpWidget(_wrap(
          ChaptersView(chapters: chapters, videoUrl: 'https://youtu.be/xyz')));
      await tester.tap(find.textContaining('Chapitres'));
      await tester.pumpAndSettle();

      // First tap
      await tester.tap(find.text('Ch 1'));
      await tester.pump();
      // Rapid second tap (within debounce window)
      await tester.tap(find.text('Ch 1'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(seeks.length, 1);

      // After debounce window
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Ch 1'));
      await tester.pump();
      expect(seeks.length, 2);
      // Let debounce timer settle before test teardown.
      await tester.pump(const Duration(milliseconds: 410));
    });
  });
}
