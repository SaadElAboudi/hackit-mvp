import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hackit_mvp_flutter/widgets/video_card.dart';

void main() {
  group('VideoCard Widget Tests', () {
    testWidgets('renders title and link text', (WidgetTester tester) async {
      const title = 'Test Video';
      const videoUrl = 'https://example.com/video';

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: VideoCard(
            title: title,
            videoUrl: videoUrl,
          ),
        ),
      ));

      expect(find.text(title), findsOneWidget);
      expect(find.text('Voir la vidéo →'), findsOneWidget);
    });

    testWidgets('shows error on invalid URL', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: VideoCard(
            title: 'Test',
            videoUrl: 'invalid-url',
          ),
        ),
      ));

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('URL invalide'), findsOneWidget);
    });

    testWidgets('has correct styling', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: VideoCard(
            title: 'Test',
            videoUrl: 'https://example.com',
          ),
        ),
      ));

      final card = find.byType(Card);
      expect(card, findsOneWidget);

      final titleText = tester.widget<Text>(find.text('Test'));
      expect(titleText.style?.fontSize, 16);
      expect(titleText.style?.fontWeight, FontWeight.bold);
    });
  });
}