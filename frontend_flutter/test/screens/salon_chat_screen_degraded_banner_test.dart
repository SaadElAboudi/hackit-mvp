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
    messages = const [];
    notifyListeners();
  }

  @override
  Future<void> closeRoom() async {}
}

Room _testRoom() {
  final now = DateTime.now();
  return Room(
    id: 'room-test-1',
    name: 'Room test',
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
  testWidgets('shows degraded backend banner when health is down',
      (tester) async {
    final provider = _FakeRoomProvider();

    await tester.pumpWidget(
      _wrap(
        SalonChatScreen(
          room: _testRoom(),
          debugInitialBackendHealth: const {'ok': false, 'status': 'down'},
          disableHealthPolling: true,
        ),
        provider,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Backend temporairement indisponible'),
        findsOneWidget);
    expect(find.text('Actualiser'), findsOneWidget);
  });

  testWidgets('does not show degraded backend banner when health is nominal',
      (tester) async {
    final provider = _FakeRoomProvider();

    await tester.pumpWidget(
      _wrap(
        SalonChatScreen(
          room: _testRoom(),
          debugInitialBackendHealth: const {
            'ok': true,
            'mode': 'REAL',
            'fallback': false,
            'gemini': {'operational': true, 'breakerActive': false},
          },
          disableHealthPolling: true,
        ),
        provider,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Actualiser'), findsNothing);
    expect(find.textContaining('Mode degrade'), findsNothing);
    expect(find.textContaining('Backend temporairement indisponible'),
        findsNothing);
  });
}
