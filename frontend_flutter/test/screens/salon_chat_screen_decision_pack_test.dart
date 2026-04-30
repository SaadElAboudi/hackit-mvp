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
    decisions = const [
      WorkspaceDecision(
        id: 'd1',
        title: 'Launch pilot',
        summary: 'Summary',
        sourceType: 'manual',
        sourceId: '',
        createdByName: 'Owner',
        createdAt: DateTime.now(),
      ),
    ];
    notifyListeners();
  }

  @override
  Future<bool> loadDecisionPack({
    String mode = 'checklist',
    bool includeOpenTasks = true,
    int limit = 10,
  }) async {
    decisionPack = DecisionPackResult(
      pack: DecisionPackPayload(
        generatedAt: DateTime.now(),
        roomId: currentRoom?.id ?? 'r1',
        roomName: currentRoom?.name ?? 'room',
        decisionCount: 1,
        taskCount: 0,
        mode: mode,
        includeOpenTasks: includeOpenTasks,
        markdown: '# Decision Pack\n\nTest payload',
      ),
      decisions: const [],
      tasks: const [],
    );
    notifyListeners();
    return true;
  }

  @override
  Future<bool> shareDecisionPack({
    required String target,
    String mode = 'executive',
    String note = '',
  }) async {
    return true;
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
  testWidgets('opens Decision Pack dialog from context panel button',
      (tester) async {
    final provider = _FakeRoomProvider();

    await tester.pumpWidget(_wrap(SalonChatScreen(room: _testRoom()), provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pack checklist'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Decision Pack'), findsWidgets);
    expect(find.textContaining('Test payload'), findsOneWidget);
  });
}
