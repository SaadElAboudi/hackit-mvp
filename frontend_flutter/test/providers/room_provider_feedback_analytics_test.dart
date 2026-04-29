import 'package:flutter_test/flutter_test.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/services/room_service.dart';

class _FakeRoomService extends RoomService {
  Future<Map<String, dynamic>> Function({
    required String roomId,
    required String messageId,
    required int rating,
    String? reason,
    Map<String, dynamic>? metadata,
  })? onSubmit;

  @override
  Future<Map<String, dynamic>> submitMessageFeedback({
    required String roomId,
    required String messageId,
    required int rating,
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    final handler = onSubmit;
    if (handler != null) {
      return handler(
        roomId: roomId,
        messageId: messageId,
        rating: rating,
        reason: reason,
        metadata: metadata,
      );
    }
    return {
      'thumbsUp': rating == 1 ? 1 : 0,
      'thumbsDown': rating == -1 ? 1 : 0,
      'userRating': rating,
      'userRatingLabel':
          rating == 1 ? 'pertinent' : (rating == 0 ? 'moyen' : 'hors_sujet'),
      'userReason': reason ?? '',
    };
  }
}

Room _room() {
  final now = DateTime.now();
  return Room(
    id: 'room-feedback-1',
    name: 'Feedback Room',
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

RoomMessage _aiMessage() {
  return RoomMessage(
    id: 'msg-ai-1',
    roomId: 'room-feedback-1',
    senderId: 'ai',
    senderName: 'IA',
    isAI: true,
    content: 'Test answer',
    type: 'ai',
    challenges: const [],
    data: const {},
    createdAt: DateTime.now(),
    thumbsUp: 0,
    thumbsDown: 0,
    userRating: 0,
    userRatingLabel: '',
  );
}

void main() {
  test('logs submitted when feedback send succeeds', () async {
    final service = _FakeRoomService();
    final events = <Map<String, dynamic>>[];

    final provider = RoomProvider(
      service: service,
      logFeedbackSignal: ({
        required String outcome,
        required String ratingLabel,
        required bool hasReason,
        required String surface,
      }) async {
        events.add({
          'outcome': outcome,
          'ratingLabel': ratingLabel,
          'hasReason': hasReason,
          'surface': surface,
        });
      },
    );

    provider.currentRoom = _room();
    provider.messages = [_aiMessage()];

    await provider.submitMessageFeedback(
      messageId: 'msg-ai-1',
      rating: 1,
      metadata: const {'surface': 'salon'},
    );
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 1);
    expect(events[0]['outcome'], 'submitted');
    expect(events[0]['ratingLabel'], 'pertinent');
    expect(events[0]['hasReason'], false);
    expect(provider.messages.first.userRating, 1);
    expect(provider.messages.first.userRatingLabel, 'pertinent');
  });

  test('logs failed and reverts optimistic feedback on error', () async {
    final service = _FakeRoomService()
      ..onSubmit = ({
        required String roomId,
        required String messageId,
        required int rating,
        String? reason,
        Map<String, dynamic>? metadata,
      }) async {
        throw Exception('feedback failed');
      };

    final events = <Map<String, dynamic>>[];
    final provider = RoomProvider(
      service: service,
      logFeedbackSignal: ({
        required String outcome,
        required String ratingLabel,
        required bool hasReason,
        required String surface,
      }) async {
        events.add({
          'outcome': outcome,
          'ratingLabel': ratingLabel,
          'hasReason': hasReason,
          'surface': surface,
        });
      },
    );

    provider.currentRoom = _room();
    provider.messages = [_aiMessage()];

    await provider.submitMessageFeedback(
      messageId: 'msg-ai-1',
      rating: -1,
      reason: 'Not relevant',
    );
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 1);
    expect(events[0]['outcome'], 'failed');
    expect(events[0]['ratingLabel'], 'hors_sujet');
    expect(events[0]['hasReason'], true);
    expect(provider.messages.first.userRating, 0);
    expect(provider.messages.first.userRatingLabel, '');
    expect(provider.actionError, contains('feedback failed'));
  });

  test('logs retried then submitted after a prior failure', () async {
    var attempts = 0;
    final service = _FakeRoomService()
      ..onSubmit = ({
        required String roomId,
        required String messageId,
        required int rating,
        String? reason,
        Map<String, dynamic>? metadata,
      }) async {
        attempts += 1;
        if (attempts == 1) {
          throw Exception('temporary failure');
        }
        return {
          'thumbsUp': 0,
          'thumbsDown': 0,
          'userRating': 0,
          'userRatingLabel': 'moyen',
          'userReason': '',
        };
      };

    final events = <String>[];
    final provider = RoomProvider(
      service: service,
      logFeedbackSignal: ({
        required String outcome,
        required String ratingLabel,
        required bool hasReason,
        required String surface,
      }) async {
        events.add(outcome);
      },
    );

    provider.currentRoom = _room();
    provider.messages = [_aiMessage()];

    await provider.submitMessageFeedback(messageId: 'msg-ai-1', rating: 0);
    await provider.submitMessageFeedback(messageId: 'msg-ai-1', rating: 0);
    await Future<void>.delayed(Duration.zero);

    expect(events, ['failed', 'retried', 'submitted']);
    expect(provider.messages.first.userRating, 0);
    expect(provider.messages.first.userRatingLabel, 'moyen');
  });
}
