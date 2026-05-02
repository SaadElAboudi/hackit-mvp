import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/screens/salon_chat_screen.dart';

class _FakeRoomProvider extends RoomProvider {
  int decisionPackShareCalls = 0;

  @override
  Future<void> openRoom(Room room) async {
    currentRoom = room;
    loadingMessages = false;
    messages = const [];
    decisions = [
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
    decisionPackAggregate = DecisionPackAggregate(
      sinceDays: 14,
      since: DateTime.now(),
      viewed: 5,
      shared: 2,
      shareFailed: 1,
    );
    slackIntegration = RoomIntegrationStatus(
      provider: 'slack',
      enabled: true,
      connected: true,
      connectedBy: 'owner-1',
      connectedAt: DateTime.now(),
      channelId: 'C123',
      parentPageId: '',
    );
    notionIntegration = RoomIntegrationStatus(
      provider: 'notion',
      enabled: true,
      connected: true,
      connectedBy: 'owner-1',
      connectedAt: DateTime.now(),
      channelId: '',
      parentPageId: 'page-1',
    );
    notifyListeners();
  }

  @override
  Future<bool> loadDecisionPack({
    String mode = 'checklist',
    bool includeOpenTasks = true,
    int limit = 10,
  }) async {
    final markdown = mode == 'executive'
        ? '# Decision Pack\n\n## Executive Decisions\n\nOwners: Alice'
        : '# Decision Pack\n\n## Decisions\n\n- Tasks: none linked yet.';
    decisionPack = DecisionPackResult(
      pack: DecisionPackPayload(
        generatedAt: DateTime.now(),
        roomId: currentRoom?.id ?? 'r1',
        roomName: currentRoom?.name ?? 'room',
        decisionCount: 1,
        taskCount: 0,
        mode: mode,
        includeOpenTasks: includeOpenTasks,
        markdown: markdown,
      ),
      decisions: const [],
      tasks: const [],
    );
    decisionPackMode = mode;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> setDecisionPackMode(String mode) async {
    return loadDecisionPack(mode: mode);
  }

  @override
  Future<bool> shareDecisionPack({
    required String target,
    String mode = 'executive',
    String note = '',
  }) async {
    decisionPackShareCalls += 1;
    lastDecisionPackShare = DecisionPackShareResult(
      id: 'share-${decisionPackShareCalls}',
      target: target,
      status: 'success',
      mode: mode,
      externalUrl: '',
      csvFileName: target == 'csv' ? 'decision-pack.csv' : '',
      csvContent: target == 'csv' ? 'a,b\n1,2' : '',
    );
    return true;
  }

  @override
  Future<bool> refreshDecisionPackReadiness() async {
    decisionPackReadiness = const DecisionPackReadiness(
      ready: true,
      score: 88,
      totalTasks: 2,
      tasksWithOwners: 2,
      tasksWithDueDates: 2,
      linkedTaskCount: 1,
      ownerCoverage: 1,
      dueDateCoverage: 1,
      linkedTaskCoverage: 0.5,
      recommendations: [],
    );
    notifyListeners();
    return true;
  }

  @override
  Future<bool> refreshDecisionPackAggregate({int sinceDays = 7}) async {
    decisionPackAggregate = DecisionPackAggregate(
      sinceDays: sinceDays,
      since: DateTime.now(),
      viewed: 10,
      shared: 4,
      shareFailed: 1,
    );
    notifyListeners();
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
  testWidgets('mode selector switches to executive and shows exec content',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider();

    await tester
        .pumpWidget(_wrap(SalonChatScreen(room: _testRoom()), provider));
    await tester.pumpAndSettle();

    // Default is 'checklist'; tap Executive to change
    await tester.tap(find.text('Executive'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Decision Pack'), findsWidgets);
    expect(find.textContaining('Executive Decisions'), findsOneWidget);
    expect(find.textContaining('## Decisions\n'), findsNothing);
  });

  testWidgets('mode selector switches back to checklist and shows task list',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider();

    await tester
        .pumpWidget(_wrap(SalonChatScreen(room: _testRoom()), provider));
    await tester.pumpAndSettle();

    // First switch to Executive
    await tester.tap(find.text('Executive'));
    await tester.pumpAndSettle();

    // Close exec dialog
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();

    // Switch back to Checklist (fires because Executive was selected)
    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Decision Pack'), findsWidgets);
    expect(find.textContaining('## Decisions'), findsOneWidget);
    expect(find.textContaining('Executive Decisions'), findsNothing);
  });

  testWidgets('shows Decision Pack share actions in context panel',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider();

    await tester
        .pumpWidget(_wrap(SalonChatScreen(room: _testRoom()), provider));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('Vues: 5'),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Vues: 5'), findsOneWidget);
    expect(
      find.textContaining('Partages: 2'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Conv.: 40%'),
      findsOneWidget,
    );
    expect(find.text('14j'), findsOneWidget);
    expect(
      find.textContaining(
        'Conversion correcte, mais surveiller les échecs',
      ),
      findsOneWidget,
    );
    expect(find.text('Repartager vers Notion'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Decision Pack → Slack'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Decision Pack → Slack'), findsOneWidget);
    expect(find.text('Decision Pack → Notion'), findsOneWidget);
    expect(find.text('Decision Pack → CSV'), findsOneWidget);
  });

  testWidgets('checks readiness before Decision Pack share', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider();

    await tester
        .pumpWidget(_wrap(SalonChatScreen(room: _testRoom()), provider));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Decision Pack → Slack'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decision Pack → Slack'));
    await tester.pumpAndSettle();

    expect(find.text('Decision Pack pret'), findsOneWidget);
    expect(find.textContaining('Score readiness 88/100'), findsOneWidget);

    await tester.tap(find.text('Partager').last);
    await tester.pumpAndSettle();

    expect(provider.decisionPackShareCalls, 1);
    expect(find.textContaining('Decision Pack partage vers Slack'),
        findsOneWidget);
  });
}
