import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/screens/salon_chat_screen.dart';

class _FakeRoomProvider extends RoomProvider {
  @override
  Future<void> openRoom(Room room) async {
    currentRoom = room;
    loadingMessages = false;
    messages = [
      RoomMessage(
        id: 'msg-ai-trust-1',
        roomId: room.id,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        content: 'Plan propose pour avancer rapidement.',
        type: 'ai',
        challenges: const [],
        data: const {
          'trust': {
            'confidence': 'moyen',
            'whyThisPlan': 'Ce plan maximise impact x rapidite pour le sprint.',
            'assumptions': [
              'Le scope reste stable sur la semaine.',
              'Les dependances critiques sont disponibles.'
            ],
            'limits': ['N inclut pas de validation legale finale.'],
          }
        },
        createdAt: DateTime.now(),
      ),
    ];
    notifyListeners();
  }

  @override
  Future<void> closeRoom() async {}
}

class _FakeRoomProviderResearchDecision extends RoomProvider {
  @override
  Future<void> openRoom(Room room) async {
    currentRoom = room;
    loadingMessages = false;
    messages = [
      RoomMessage(
        id: 'msg-research-trust-1',
        roomId: room.id,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        content: 'Synthese recherche.',
        type: 'research',
        challenges: const [],
        data: const {
          'videoTitle': 'Source',
          'videoUrl': 'https://example.com/video',
          'trust': {
            'confidence': 'moyen',
            'whyThisPlan': 'Bloc trust recherche.',
            'assumptions': ['Hypothese recherche'],
            'limits': ['Limite recherche'],
          }
        },
        createdAt: DateTime.now(),
      ),
      RoomMessage(
        id: 'msg-decision-trust-1',
        roomId: room.id,
        senderId: 'ai',
        senderName: 'IA',
        isAI: true,
        content: 'Synthese decision.',
        type: 'decision',
        challenges: const [],
        data: const {
          'decisions': ['Decision A'],
          'risks': ['Risque A'],
          'nextSteps': ['Etape A'],
          'trust': {
            'confidence': 'faible',
            'whyThisPlan': 'Bloc trust decision.',
            'assumptions': ['Hypothese decision'],
            'limits': ['Limite decision'],
          }
        },
        createdAt: DateTime.now(),
      ),
    ];
    notifyListeners();
  }

  @override
  Future<void> closeRoom() async {}
}

Room _testRoom() {
  final now = DateTime.now();
  return Room(
    id: 'room-test-trust',
    name: 'Room trust',
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
  testWidgets('renders explainability block for AI trust payload',
      (tester) async {
    final provider = _FakeRoomProvider();

    await tester.pumpWidget(
      _wrap(
        SalonChatScreen(room: _testRoom(), disableHealthPolling: true),
        provider,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Pourquoi ce plan'), findsOneWidget);
    expect(find.textContaining('Confiance: Moyen'), findsOneWidget);
    expect(
      find.text('Ce plan maximise impact x rapidite pour le sprint.'),
      findsOneWidget,
    );
    expect(find.text('Hypotheses'), findsOneWidget);
    expect(find.text('Limites'), findsOneWidget);
  });

  testWidgets('renders explainability block for research and decision cards',
      (tester) async {
    final provider = _FakeRoomProviderResearchDecision();

    await tester.pumpWidget(
      _wrap(
        SalonChatScreen(room: _testRoom(), disableHealthPolling: true),
        provider,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Bloc trust recherche.'), findsOneWidget);
    expect(find.text('Bloc trust decision.'), findsOneWidget);
    expect(find.text('Limite recherche'), findsOneWidget);
    expect(find.text('Limite decision'), findsOneWidget);
  });
}
