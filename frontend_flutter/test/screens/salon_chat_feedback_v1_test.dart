import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/screens/salon_chat_screen.dart';

class _FakeRoomProvider extends RoomProvider {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<void> openRoom(Room room) async {
    currentRoom = room;
    loadingMessages = false;
    messages = [
      RoomMessage(
        id: 'msg-ai-1',
        roomId: room.id,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        content: 'Reponse de test',
        type: 'ai',
        challenges: const [],
        data: const {},
        createdAt: DateTime.now(),
        thumbsUp: 1,
        thumbsDown: 1,
        userRating: 0,
        userRatingLabel: '',
      ),
    ];
    notifyListeners();
  }

  @override
  Future<void> closeRoom() async {}

  @override
  Future<void> submitMessageFeedback({
    required String messageId,
    required int rating,
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    calls.add({
      'messageId': messageId,
      'rating': rating,
      'reason': reason,
      'metadata': metadata,
    });
  }
}

Room _testRoom() {
  final now = DateTime.now();
  return Room(
    id: 'room-test-feedback',
    name: 'Room test feedback',
    type: 'group',
    purpose: 'test',
    templateId: '',
    templateVersion: '',
    visibility: 'invite_only',
    ownerId: 'owner-1',
    members: const [
      RoomMember(userId: 'owner-1', displayName: 'Owner', role: 'owner'),
    ],
    aiDirectives: '',
    pinnedArtifactId: null,
    lastActivityAt: now,
    updatedAt: now,
  );
}

Widget _wrap(Widget child, RoomProvider provider) {
  return ChangeNotifierProvider<RoomProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
      'captures pertinent/moyen/hors-sujet feedback with optional reason',
      (tester) async {
    final provider = _FakeRoomProvider();

    await tester.pumpWidget(
      _wrap(
        SalonChatScreen(
          room: _testRoom(),
          disableHealthPolling: true,
        ),
        provider,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Pertinent'), findsOneWidget);
    expect(find.text('Moyen'), findsOneWidget);
    expect(find.text('Hors sujet'), findsOneWidget);

    await tester.tap(find.text('Pertinent'));
    await tester.pumpAndSettle();

    expect(provider.calls.length, 1);
    expect(provider.calls[0]['rating'], 1);
    expect(provider.calls[0]['reason'], isNull);

    await tester.tap(find.text('Moyen'));
    await tester.pumpAndSettle();

    expect(find.text('Ajouter un detail (optionnel)'), findsOneWidget);
    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();

    expect(provider.calls.length, 2);
    expect(provider.calls[1]['rating'], 0);
    expect(provider.calls[1]['reason'], isNull);

    await tester.tap(find.text('Hors sujet'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Pas assez specifique pour notre contexte',
    );
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(provider.calls.length, 3);
    expect(provider.calls[2]['rating'], -1);
    expect(provider.calls[2]['reason'],
        'Pas assez specifique pour notre contexte');
  });
}
