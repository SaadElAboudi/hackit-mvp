import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/screens/room_tasks_screen.dart';

// ────────────────────────────────────────────────────────────
// Fake provider
// ────────────────────────────────────────────────────────────

class _FakeRoomProvider extends RoomProvider {
  List<WorkspaceDecision> fakeDecisions;
  List<WorkspaceTask> fakeTasks;

  // Tracking
  WorkspaceDecision? lastConvertedDecision;
  List<Map<String, dynamic>>? lastTaskDrafts;
  int convertCalls = 0;
  int extractCalls = 0;
  bool extractPersist = false;
  int updateDecisionCalls = 0;
  String? lastDecisionStatus;
  String? lastDecisionOwner;

  _FakeRoomProvider({
    this.fakeDecisions = const [],
    this.fakeTasks = const [],
  }) {
    decisions = List.of(fakeDecisions);
    tasks = List.of(fakeTasks);
    loadingMessages = false;
    loadingRooms = false;
  }

  @override
  Future<List<WorkspaceTask>?> convertDecisionToTasks(
    WorkspaceDecision decision, {
    required List<Map<String, dynamic>> taskDrafts,
  }) async {
    convertCalls++;
    lastConvertedDecision = decision;
    lastTaskDrafts = taskDrafts;
    final created = taskDrafts
        .map(
          (d) => WorkspaceTask(
            id: 'task-new-${taskDrafts.indexOf(d)}',
            decisionId: decision.id,
            title: d['title']?.toString() ?? '',
            description: '',
            status: 'todo',
            ownerId: '',
            ownerName: '',
            dueDate: null,
            updatedAt: DateTime.now(),
          ),
        )
        .toList();
    tasks = [...tasks, ...created];
    notifyListeners();
    return created;
  }

  @override
  Future<DecisionExtractionResult?> extractDecisionsFromChat({
    bool persist = false,
    int recentLimit = 30,
  }) async {
    extractCalls++;
    extractPersist = persist;
    return const DecisionExtractionResult(
      persisted: false,
      extracted: [
        ExtractedDecisionDraft(
          title: 'Decision IA test',
          summary: 'Resume test',
          tasks: [
            ExtractedTaskDraft(
              title: 'Tache IA 1',
              description: '',
            ),
          ],
        ),
      ],
      decisions: [],
      tasks: [],
      missionId: null,
    );
  }

  @override
  Future<WorkspaceDecision?> updateDecision(
    WorkspaceDecision decision, {
    String? title,
    String? summary,
    String? status,
    String? ownerId,
    String? ownerName,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) async {
    updateDecisionCalls++;
    lastDecisionStatus = status;
    lastDecisionOwner = ownerName;
    final updated = WorkspaceDecision(
      id: decision.id,
      title: title ?? decision.title,
      summary: summary ?? decision.summary,
      sourceType: decision.sourceType,
      sourceId: decision.sourceId,
      createdByName: decision.createdByName,
      createdAt: decision.createdAt,
      status: status ?? decision.status,
      ownerId: ownerId ?? decision.ownerId,
      ownerName: ownerName ?? decision.ownerName,
      dueDate: clearDueDate ? null : (dueDate ?? decision.dueDate),
      approvedAt: decision.approvedAt,
    );
    final idx = decisions.indexWhere((d) => d.id == decision.id);
    if (idx >= 0) {
      decisions[idx] = updated;
    }
    notifyListeners();
    return updated;
  }
}

// ────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────

final _now = DateTime.now();

WorkspaceDecision _decision({
  String id = 'd1',
  String title = 'Approuver le budget Q2',
  String summary = 'Contexte budget',
}) =>
    WorkspaceDecision(
      id: id,
      title: title,
      summary: summary,
      sourceType: 'manual',
      sourceId: '',
      createdByName: 'Test',
      createdAt: _now,
    );

WorkspaceTask _task({
  String id = 't1',
  String title = 'Tache 1',
  String decisionId = '',
  String status = 'todo',
}) =>
    WorkspaceTask(
      id: id,
      decisionId: decisionId,
      title: title,
      description: '',
      status: status,
      ownerId: '',
      ownerName: '',
      dueDate: null,
      updatedAt: _now,
    );

Widget _wrap(RoomProvider provider) =>
    ChangeNotifierProvider<RoomProvider>.value(
      value: provider,
      child: MaterialApp(
        home: RoomTasksScreen(
          roomName: 'Test Channel',
          onEditTask: (_) async {},
        ),
      ),
    );

// ────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────

void main() {
  testWidgets('shows decisions panel when decisions exist', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeDecisions: [_decision()],
      fakeTasks: [],
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 decision'), findsOneWidget);
    expect(find.text('Convertir'), findsOneWidget);
  });

  testWidgets('hides decisions panel when no decisions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(fakeDecisions: [], fakeTasks: []);

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.text('Convertir'), findsNothing);
  });

  testWidgets('extract IA action button is present in AppBar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider();

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    // Tooltip on the AI extract button
    expect(
      find.byTooltip('Extraire decisions et taches par IA'),
      findsOneWidget,
    );
  });

  testWidgets('tapping AI extract opens preview dialog and calls provider',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider();

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Extraire decisions et taches par IA'));
    await tester.pumpAndSettle();

    // extractDecisionsFromChat was called for the preview
    expect(provider.extractCalls, greaterThanOrEqualTo(1));
    // Preview dialog shows extracted decision title
    expect(find.textContaining('Decision IA test'), findsOneWidget);
  });

  testWidgets(
    'convert decision dialog shows decisions list and creates tasks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final decision = _decision();
      final provider = _FakeRoomProvider(fakeDecisions: [decision]);

      await tester.pumpWidget(_wrap(provider));
      await tester.pumpAndSettle();

      // Open convert dialog from AppBar
      await tester.tap(
        find.byTooltip('Convertir une decision en taches'),
      );
      await tester.pumpAndSettle();

      // Decision is listed
      expect(find.text('Approuver le budget Q2'), findsOneWidget);

      // Select the decision
      await tester.tap(find.text('Approuver le budget Q2'));
      await tester.pumpAndSettle();

      // Tap "Suivant"
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();

      // Task definition step is shown
      expect(find.textContaining('Taches pour'), findsOneWidget);

      // Fill task title
      await tester.enterText(
        find.widgetWithText(TextField, 'Ex: Rediger le brief').first,
        'Preparer presentation',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('Creer les taches'));
      await tester.pumpAndSettle();

      expect(provider.convertCalls, 1);
      expect(provider.lastConvertedDecision?.id, decision.id);
      expect(provider.lastTaskDrafts, isNotEmpty);
      expect(provider.lastTaskDrafts!.first['title'], 'Preparer presentation');
    },
  );

  testWidgets('decision workflow dialog updates status and owner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final decision = _decision();
    final provider = _FakeRoomProvider(fakeDecisions: [decision]);

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    // Expand decisions panel and open edit workflow action
    await tester.tap(find.textContaining('1 decision'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editer workflow').first);
    await tester.pumpAndSettle();

    expect(find.text('Workflow de decision'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nom du proprietaire de la decision'),
      'Alice',
    );

    await tester.tap(find.text('Sauvegarder'));
    await tester.pumpAndSettle();

    expect(provider.updateDecisionCalls, 1);
    expect(provider.lastDecisionStatus, 'draft');
    expect(provider.lastDecisionOwner, 'Alice');
  });
}
