import 'package:flutter_test/flutter_test.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/services/room_service.dart';

class _FakeRoomService extends RoomService {
  Future<DecisionPackResult> Function({
    required String roomId,
    required String mode,
    required bool includeOpenTasks,
    required int limit,
  })? onGetDecisionPack;

  Future<void> Function({
    required String roomId,
    required String target,
    required String mode,
    required String note,
  })? onShareDecisionPack;
  int shareCalls = 0;
  int trackEventCalls = 0;
  int readinessCalls = 0;
  String lastShareTarget = '';

  @override
  Future<DecisionPackResult> getDecisionPack(
    String roomId, {
    String mode = 'checklist',
    bool includeOpenTasks = true,
    int limit = 10,
  }) async {
    final handler = onGetDecisionPack;
    if (handler != null) {
      return handler(
        roomId: roomId,
        mode: mode,
        includeOpenTasks: includeOpenTasks,
        limit: limit,
      );
    }
    return DecisionPackResult(
      pack: DecisionPackPayload(
        generatedAt: DateTime.now(),
        roomId: roomId,
        roomName: 'Room',
        decisionCount: 1,
        taskCount: 1,
        mode: mode,
        includeOpenTasks: includeOpenTasks,
        markdown: '# Decision Pack',
      ),
      decisions: const [],
      tasks: const [],
    );
  }

  @override
  Future<void> shareDecisionPack(
    String roomId, {
    required String target,
    String mode = 'executive',
    String note = '',
  }) async {
    shareCalls += 1;
    lastShareTarget = target;
    final handler = onShareDecisionPack;
    if (handler != null) {
      return handler(roomId: roomId, target: target, mode: mode, note: note);
    }
  }

  @override
  Future<List<RoomShareHistoryItem>> listShareHistory(
    String roomId, {
    String? target,
    String? status,
    int limit = 20,
  }) async {
    return [
      RoomShareHistoryItem(
        id: 'h1',
        target: target ?? lastShareTarget,
        status: 'success',
        actorName: 'Owner',
        note: 'decision pack',
        summary: 'ok',
        retries: 0,
        errorCode: '',
        errorMessage: '',
        externalId: '',
        externalUrl: '',
        createdAt: DateTime.now(),
      ),
    ];
  }

  @override
  Future<void> trackDecisionPackEvent(
    String roomId, {
    required String eventType,
    required String mode,
    String target = '',
    Map<String, dynamic>? metadata,
  }) async {
    trackEventCalls += 1;
  }

  @override
  Future<DecisionPackReadiness> getDecisionPackReadiness(String roomId) async {
    readinessCalls += 1;
    return const DecisionPackReadiness(
      ready: false,
      score: 62,
      totalTasks: 2,
      tasksWithOwners: 1,
      tasksWithDueDates: 1,
      linkedTaskCount: 1,
      ownerCoverage: 0.5,
      dueDateCoverage: 0.5,
      linkedTaskCoverage: 0.5,
      recommendations: ['Assign owners to the remaining open tasks.'],
    );
  }

  @override
  Future<DecisionPackAggregate> getDecisionPackAggregate(
    String roomId, {
    int sinceDays = 7,
  }) async {
    return DecisionPackAggregate(
      sinceDays: sinceDays,
      since: DateTime.now(),
      viewed: 3,
      shared: 1,
      shareFailed: 0,
    );
  }
}

Room _room() {
  final now = DateTime.now();
  return Room(
    id: 'room-dp-1',
    name: 'Decision Room',
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

void main() {
  test('loadDecisionPack stores payload on success', () async {
    final service = _FakeRoomService();
    final provider = RoomProvider(service: service)..currentRoom = _room();

    final ok = await provider.loadDecisionPack(mode: 'executive');

    expect(ok, isTrue);
    expect(provider.decisionPack, isNotNull);
    expect(provider.decisionPack!.pack.mode, 'executive');
    expect(provider.loadingDecisionPack, isFalse);
    expect(service.trackEventCalls, 1);
  });

  test('loadDecisionPack sets actionError on failure', () async {
    final service = _FakeRoomService()
      ..onGetDecisionPack = ({
        required String roomId,
        required String mode,
        required bool includeOpenTasks,
        required int limit,
      }) async {
        throw Exception('decision pack failed');
      };
    final provider = RoomProvider(service: service)..currentRoom = _room();

    final ok = await provider.loadDecisionPack(mode: 'checklist');

    expect(ok, isFalse);
    expect(provider.actionError, contains('decision pack failed'));
    expect(provider.loadingDecisionPack, isFalse);
  });

  test('shareDecisionPack returns false and captures failure', () async {
    final service = _FakeRoomService()
      ..onShareDecisionPack = ({
        required String roomId,
        required String target,
        required String mode,
        required String note,
      }) async {
        throw Exception('share failed');
      };
    final provider = RoomProvider(service: service)..currentRoom = _room();

    final ok = await provider.shareDecisionPack(target: 'slack');

    expect(ok, isFalse);
    expect(provider.actionError, contains('share failed'));
  });

  test('shareDecisionPack success refreshes share history', () async {
    final service = _FakeRoomService();
    final provider = RoomProvider(service: service)..currentRoom = _room();

    final ok = await provider.shareDecisionPack(target: 'notion');

    expect(ok, isTrue);
    expect(service.shareCalls, 1);
    expect(provider.shareHistory, isNotEmpty);
    expect(provider.shareHistory.first.target, 'notion');
  });

  test('refreshDecisionPackReadiness stores quality gate', () async {
    final service = _FakeRoomService();
    final provider = RoomProvider(service: service)..currentRoom = _room();

    final ok = await provider.refreshDecisionPackReadiness();

    expect(ok, isTrue);
    expect(service.readinessCalls, 1);
    expect(provider.decisionPackReadiness?.score, 62);
    expect(provider.decisionPackReadiness?.ready, isFalse);
    expect(provider.loadingDecisionPackReadiness, isFalse);
  });

  test('refreshDecisionPackAggregate stores counters', () async {
    final service = _FakeRoomService();
    final provider = RoomProvider(service: service)..currentRoom = _room();

    final ok = await provider.refreshDecisionPackAggregate(sinceDays: 14);

    expect(ok, isTrue);
    expect(provider.decisionPackAggregate, isNotNull);
    expect(provider.decisionPackAggregate!.viewed, 3);
    expect(provider.loadingDecisionPackAggregate, isFalse);
  });
}
