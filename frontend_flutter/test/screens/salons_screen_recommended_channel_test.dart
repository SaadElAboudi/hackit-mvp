import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/screens/salons_screen.dart';

class _FakeRoomProvider extends RoomProvider {
  _FakeRoomProvider({
    this.withInsights = true,
    this.topByFeedbackId = 'product',
    this.topByD7Id = 'product',
    this.underperformingIds = const ['marketing'],
  });

  final bool withInsights;
  final String? topByFeedbackId;
  final String? topByD7Id;
  final List<String> underperformingIds;
  String? lastTemplateId;
  String? lastTemplateVersion;
  String? lastName;
  String? lastMissionPrompt;
  int openRoomCalls = 0;
  int createMissionCalls = 0;
  int createCalls = 0;

  @override
  Future<void> loadRooms() async {
    loadingRooms = false;
    rooms = const [];
    notifyListeners();
  }

  @override
  Future<void> loadTemplates() async {
    loadingTemplates = false;
    templates = const [
      DomainTemplate(
        id: 'product',
        version: 'v1',
        versionWeights: {'v1': 100},
        name: 'Produit',
        emoji: '🚀',
        description: 'Roadmap et priorisation',
        purpose: 'Collaboration produit',
        starterPrompts: ['Plan roadmap Q3'],
      ),
      DomainTemplate(
        id: 'marketing',
        version: 'v1',
        versionWeights: {'v1': 100},
        name: 'Marketing',
        emoji: '📣',
        description: 'Acquisition et croissance',
        purpose: 'Collaboration marketing',
        starterPrompts: ['Plan acquisition 30 jours'],
      ),
    ];
    notifyListeners();
  }

  @override
  Future<void> loadTemplateStats({
    bool force = false,
    int? sinceDays,
    String? groupBy,
  }) async {
    loadingTemplateStats = false;
    if (!withInsights) {
      templateStats = const [];
      templateInsights = null;
      notifyListeners();
      return;
    }

    const productStats = DomainTemplateStats(
      templateId: 'product',
      templateVersion: 'v1',
      name: 'Produit',
      emoji: '🚀',
      description: 'Roadmap et priorisation',
      roomsCreated: 12,
      messagesSent: 220,
      feedbackUp: 18,
      feedbackDown: 3,
      feedbackAverage: 0.64,
      isLowSample: false,
      winner: true,
      d1RetainedRooms: 9,
      d7RetainedRooms: 6,
      d1RetentionRate: 75,
      d7RetentionRate: 50,
    );

    const marketingStats = DomainTemplateStats(
      templateId: 'marketing',
      templateVersion: 'v1',
      name: 'Marketing',
      emoji: '📣',
      description: 'Acquisition et croissance',
      roomsCreated: 8,
      messagesSent: 120,
      feedbackUp: 9,
      feedbackDown: 5,
      feedbackAverage: 0.2,
      isLowSample: false,
      winner: false,
      d1RetainedRooms: 5,
      d7RetainedRooms: 2,
      d1RetentionRate: 62.5,
      d7RetentionRate: 25,
    );

    final byId = <String, DomainTemplateStats>{
      'product': productStats,
      'marketing': marketingStats,
    };

    templateStats = const [productStats, marketingStats];
    templateInsights = DomainTemplateInsights(
      topByFeedback:
          topByFeedbackId == null ? null : byId[topByFeedbackId ?? ''],
      topByD7Retention: topByD7Id == null ? null : byId[topByD7Id ?? ''],
      underperformingTemplates: underperformingIds
          .map((id) => byId[id])
          .whereType<DomainTemplateStats>()
          .toList(),
    );
    notifyListeners();
  }

  @override
  Future<Room?> createRoom({
    required String name,
    String type = 'group',
    String? displayName,
    String? templateId,
    String? templateVersion,
  }) async {
    createCalls += 1;
    lastName = name;
    lastTemplateId = templateId;
    lastTemplateVersion = templateVersion;
    final now = DateTime.now();
    return Room(
      id: 'room-recommended-1',
      name: name,
      type: 'group',
      purpose: 'test',
      templateId: templateId ?? '',
      templateVersion: templateVersion ?? '',
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

  @override
  Future<void> openRoom(Room room) async {
    openRoomCalls += 1;
    currentRoom = room;
    loadingMessages = false;
    messages = const [];
    notifyListeners();
  }

  @override
  Future<bool> createMission(String prompt, {String agentType = 'auto'}) async {
    createMissionCalls += 1;
    lastMissionPrompt = prompt;
    return true;
  }
}

Widget _wrap(RoomProvider provider) {
  return ChangeNotifierProvider<RoomProvider>.value(
    value: provider,
    child: const MaterialApp(home: SalonsScreen()),
  );
}

void main() {
  testWidgets(
      'shows recommended action and creates room with recommended template',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider();

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modele recommande:'), findsOneWidget);
    expect(find.text('Creer channel recommande'), findsOneWidget);

    await tester.tap(find.text('Creer channel recommande'));
    await tester.pumpAndSettle();

    expect(provider.createCalls, 1);
    expect(provider.openRoomCalls, greaterThanOrEqualTo(1));
    expect(provider.createMissionCalls, 1);
    expect(provider.lastMissionPrompt, isNotEmpty);
    expect(provider.lastTemplateId, 'product');
    expect(provider.lastTemplateVersion, isNull);
    expect(provider.lastName, isNotEmpty);
  });

  testWidgets('does not show recommended action without insights',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider(withInsights: false);
    provider.templates = const [
      DomainTemplate(
        id: 'product',
        version: 'v1',
        versionWeights: {'v1': 100},
        name: 'Produit',
        emoji: '🚀',
        description: 'Roadmap et priorisation',
        purpose: 'Collaboration produit',
        starterPrompts: [],
      ),
    ];
    provider.templateStats = const [];
    provider.templateInsights = null;

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.text('Creer channel recommande'), findsNothing);
  });

  testWidgets(
      'falls back to top D7 recommendation when top feedback is underperforming',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider(
      topByFeedbackId: 'product',
      topByD7Id: 'marketing',
      underperformingIds: const ['product'],
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modele recommande: Marketing'), findsOneWidget);

    await tester.tap(find.text('Creer channel recommande'));
    await tester.pumpAndSettle();

    expect(provider.createCalls, 1);
    expect(provider.lastTemplateId, 'marketing');
  });

  testWidgets(
      'does not show recommendation when all top candidates are blocked',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _FakeRoomProvider(
      topByFeedbackId: 'product',
      topByD7Id: 'marketing',
      underperformingIds: const ['product', 'marketing'],
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modele recommande:'), findsNothing);
    expect(find.text('Creer channel recommande'), findsNothing);
  });
}
