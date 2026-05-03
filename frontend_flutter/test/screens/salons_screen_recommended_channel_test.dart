import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/screens/salons_screen.dart';

class _FakeRoomProvider extends RoomProvider {
  _FakeRoomProvider({this.withInsights = true});

  final bool withInsights;
  String? lastTemplateId;
  String? lastTemplateVersion;
  String? lastName;
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

    templateStats = [productStats, marketingStats];
    templateInsights = DomainTemplateInsights(
      topByFeedback: productStats,
      topByD7Retention: productStats,
      underperformingTemplates: [marketingStats],
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
    return null;
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
}
