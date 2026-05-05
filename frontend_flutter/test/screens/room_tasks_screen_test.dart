import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  DateTime? lastDecisionDueDate;
  bool lastDecisionClearDueDate = false;
  int updateTaskCalls = 0;
  String? lastTaskStatus;
  String? lastTaskOwner;
  DateTime? lastTaskDueDate;
  bool lastTaskClearDueDate = false;

  _FakeRoomProvider({
    this.fakeDecisions = const [],
    this.fakeTasks = const [],
    ExecutionPulse? fakeExecutionPulse,
  }) {
    decisions = List.of(fakeDecisions);
    tasks = List.of(fakeTasks);
    executionPulse = fakeExecutionPulse;
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
    lastDecisionDueDate = dueDate;
    lastDecisionClearDueDate = clearDueDate;
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

  @override
  Future<WorkspaceTask?> updateTask(
    WorkspaceTask task, {
    String? title,
    String? description,
    String? status,
    String? ownerId,
    String? ownerName,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) async {
    updateTaskCalls++;
    lastTaskStatus = status;
    lastTaskOwner = ownerName;
    lastTaskDueDate = dueDate;
    lastTaskClearDueDate = clearDueDate;
    final updated = WorkspaceTask(
      id: task.id,
      decisionId: task.decisionId,
      title: title ?? task.title,
      description: description ?? task.description,
      status: status ?? task.status,
      ownerId: ownerId ?? task.ownerId,
      ownerName: ownerName ?? task.ownerName,
      dueDate: clearDueDate ? null : (dueDate ?? task.dueDate),
      updatedAt: DateTime.now(),
    );
    final idx = tasks.indexWhere((entry) => entry.id == task.id);
    if (idx >= 0) {
      tasks[idx] = updated;
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
  String ownerName = 'Alice',
  DateTime? dueDate,
}) =>
    WorkspaceTask(
      id: id,
      decisionId: decisionId,
      title: title,
      description: '',
      status: status,
      ownerId: ownerName.isEmpty ? '' : 'owner-$id',
      ownerName: ownerName,
      dueDate: dueDate,
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

  testWidgets('shows execution pulse recommendations and focus items',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'critical',
        score: 42,
        criticalCount: 3,
        warningCount: 2,
        overdueTasks: 1,
        dueSoonTasks: 1,
        blockedTasks: 1,
        unassignedTasks: 0,
        overdueDecisions: 1,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 1,
        staleReviewDecisions: 0,
        recommendations: const [
          '1 decision depasse son echeance.',
          '1 tache est bloquee et demande un debloquage.',
        ],
        focusItems: const [
          ExecutionPulseFocusItem(
            kind: 'decision',
            itemId: 'd1',
            severity: 'critical',
            title: 'Approuver le budget Q2',
            status: 'review',
            ownerName: 'Alice',
            dueDate: null,
            subtitle: 'Decision en retard • Alice',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.text('Execution pulse'), findsOneWidget);
    expect(find.text('Critique'), findsOneWidget);
    expect(find.textContaining('decision depasse'), findsOneWidget);
    expect(find.text('A traiter maintenant'), findsOneWidget);
    expect(find.text('Approuver le budget Q2'), findsOneWidget);
  });

  testWidgets('opens execution digest dialog and copies content',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          clipboardText = args?['text']?.toString();
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final provider = _FakeRoomProvider(
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 74,
        criticalCount: 0,
        warningCount: 2,
        overdueTasks: 0,
        dueSoonTasks: 1,
        blockedTasks: 0,
        unassignedTasks: 1,
        overdueDecisions: 0,
        dueSoonDecisions: 1,
        decisionsWithoutOwner: 1,
        staleReviewDecisions: 0,
        recommendations: const [
          '2 engagements arrivent a echeance dans les 3 prochains jours.',
        ],
        focusItems: const [
          ExecutionPulseFocusItem(
            kind: 'task',
            itemId: 't-digest',
            severity: 'warning',
            title: 'Preparer le support client',
            status: 'todo',
            ownerName: '',
            dueDate: null,
            subtitle: 'Tache a suivre sous 3 jours',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ouvrir le digest execution'));
    await tester.pumpAndSettle();

    expect(find.text('Digest execution'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);

    await tester.tap(find.text('Copier le digest'));
    await tester.pumpAndSettle();

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, contains('Digest execution - Test Channel'));
    expect(clipboard?.text, contains('Preparer le support client'));
    expect(find.text('Digest execution copie'), findsOneWidget);
  });

  testWidgets('pulse quick filters narrow visible task cards', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeTasks: [
        _task(
          id: 't-urgent',
          title: 'Task urgent',
          dueDate: DateTime.now().add(const Duration(days: 1)),
        ),
        _task(
          id: 't-blocked',
          title: 'Task blocked',
          status: 'blocked',
          dueDate: DateTime.now().add(const Duration(days: 5)),
        ),
        _task(
          id: 't-unassigned',
          title: 'Task no owner',
          ownerName: '',
        ),
      ],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 68,
        criticalCount: 1,
        warningCount: 2,
        overdueTasks: 0,
        dueSoonTasks: 1,
        blockedTasks: 1,
        unassignedTasks: 1,
        overdueDecisions: 0,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['3 points de vigilance.'],
        focusItems: const [],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(find.text('Task urgent'), findsOneWidget);
    expect(find.text('Task blocked'), findsOneWidget);
    expect(find.text('Task no owner'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Bloquees'));
    await tester.pumpAndSettle();

    expect(find.text('Task blocked'), findsOneWidget);
    expect(find.text('Task urgent'), findsNothing);
    expect(find.text('Task no owner'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Sans owner'));
    await tester.pumpAndSettle();

    expect(find.text('Task no owner'), findsOneWidget);
    expect(find.text('Task blocked'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Urgent'));
    await tester.pumpAndSettle();

    expect(find.text('Task urgent'), findsOneWidget);
    expect(find.text('Task no owner'), findsNothing);
  });

  testWidgets('tapping decision focus item expands highlighted decision',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeDecisions: [_decision(id: 'd-focus')],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'critical',
        score: 51,
        criticalCount: 1,
        warningCount: 0,
        overdueTasks: 0,
        dueSoonTasks: 0,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 1,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 decision depasse son echeance.'],
        focusItems: const [
          ExecutionPulseFocusItem(
            kind: 'decision',
            itemId: 'd-focus',
            severity: 'critical',
            title: 'Approuver le budget Q2',
            status: 'review',
            ownerName: 'Alice',
            dueDate: null,
            subtitle: 'Decision en retard • Alice',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approuver le budget Q2').last);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Editer workflow'), findsOneWidget);
  });

  testWidgets('decision quick action moves draft item into review',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeDecisions: [_decision(id: 'd-review')],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'critical',
        score: 49,
        criticalCount: 1,
        warningCount: 0,
        overdueTasks: 0,
        dueSoonTasks: 0,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 1,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 decision depasse son echeance.'],
        focusItems: const [
          ExecutionPulseFocusItem(
            kind: 'decision',
            itemId: 'd-review',
            severity: 'critical',
            title: 'Approuver le budget Q2',
            status: 'draft',
            ownerName: 'Alice',
            dueDate: null,
            subtitle: 'Decision en retard • Alice',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Passer en revue'));
    await tester.pumpAndSettle();

    expect(provider.updateDecisionCalls, 1);
    expect(provider.lastDecisionStatus, 'review');
  });

  testWidgets('task quick action relaunches blocked task', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeTasks: [
        _task(
          id: 't-blocked',
          title: 'Corriger le playbook',
          status: 'blocked',
          ownerName: 'Lina',
        ),
      ],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'critical',
        score: 40,
        criticalCount: 1,
        warningCount: 0,
        overdueTasks: 0,
        dueSoonTasks: 0,
        blockedTasks: 1,
        unassignedTasks: 0,
        overdueDecisions: 0,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 tache est bloquee.'],
        focusItems: const [
          ExecutionPulseFocusItem(
            kind: 'task',
            itemId: 't-blocked',
            severity: 'critical',
            title: 'Corriger le playbook',
            status: 'blocked',
            ownerName: 'Lina',
            dueDate: null,
            subtitle: 'Tache bloquee • Lina',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Relancer'));
    await tester.pumpAndSettle();

    expect(provider.updateTaskCalls, 1);
    expect(provider.lastTaskStatus, 'in_progress');
  });

  testWidgets('decision quick action can set due date when missing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeDecisions: [_decision(id: 'd-due', title: 'Valider le plan sprint')],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 70,
        criticalCount: 0,
        warningCount: 1,
        overdueTasks: 0,
        dueSoonTasks: 0,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 0,
        dueSoonDecisions: 1,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 decision sans echeance.'],
        focusItems: const [
          ExecutionPulseFocusItem(
            kind: 'decision',
            itemId: 'd-due',
            severity: 'warning',
            title: 'Valider le plan sprint',
            status: 'approved',
            ownerName: 'Alice',
            dueDate: null,
            subtitle: 'Decision sans echeance • Alice',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gerer l echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixer echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    expect(provider.updateDecisionCalls, 1);
    expect(provider.lastDecisionDueDate, isNotNull);
    expect(
      DateUtils.dateOnly(provider.lastDecisionDueDate!),
      DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1))),
    );
  });

  testWidgets('task quick action can set due date when missing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeTasks: [
        _task(
          id: 't-due',
          title: 'Documenter la retrospective',
          status: 'todo',
          ownerName: 'Lina',
        ),
      ],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 73,
        criticalCount: 0,
        warningCount: 1,
        overdueTasks: 0,
        dueSoonTasks: 1,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 0,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 tache sans echeance.'],
        focusItems: const [
          ExecutionPulseFocusItem(
            kind: 'task',
            itemId: 't-due',
            severity: 'warning',
            title: 'Documenter la retrospective',
            status: 'todo',
            ownerName: 'Lina',
            dueDate: null,
            subtitle: 'Tache sans echeance • Lina',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gerer l echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixer echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    expect(provider.updateTaskCalls, 1);
    expect(provider.lastTaskDueDate, isNotNull);
    expect(
      DateUtils.dateOnly(provider.lastTaskDueDate!),
      DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1))),
    );
  });

  testWidgets('decision quick action can clear due date when present',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeDecisions: [_decision(id: 'd-clear', title: 'Arbitrer la roadmap')],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 72,
        criticalCount: 0,
        warningCount: 1,
        overdueTasks: 0,
        dueSoonTasks: 0,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 0,
        dueSoonDecisions: 1,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 decision a echeance ajuster.'],
        focusItems: [
          ExecutionPulseFocusItem(
            kind: 'decision',
            itemId: 'd-clear',
            severity: 'warning',
            title: 'Arbitrer la roadmap',
            status: 'approved',
            ownerName: 'Alice',
            dueDate: DateTime.now().add(const Duration(days: 3)),
            subtitle: 'Decision planifiee • Alice',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gerer l echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer echeance'));
    await tester.pumpAndSettle();

    expect(provider.updateDecisionCalls, 1);
    expect(provider.lastDecisionClearDueDate, isTrue);
    expect(provider.lastDecisionDueDate, isNull);
  });

  testWidgets('task quick action can clear due date when present',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final provider = _FakeRoomProvider(
      fakeTasks: [
        _task(
          id: 't-clear',
          title: 'Publier le retro report',
          status: 'todo',
          ownerName: 'Lina',
          dueDate: DateTime.now().add(const Duration(days: 4)),
        ),
      ],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 75,
        criticalCount: 0,
        warningCount: 1,
        overdueTasks: 0,
        dueSoonTasks: 1,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 0,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 tache a echeance ajuster.'],
        focusItems: [
          ExecutionPulseFocusItem(
            kind: 'task',
            itemId: 't-clear',
            severity: 'warning',
            title: 'Publier le retro report',
            status: 'todo',
            ownerName: 'Lina',
            dueDate: DateTime.now().add(const Duration(days: 4)),
            subtitle: 'Tache planifiee • Lina',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gerer l echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer echeance'));
    await tester.pumpAndSettle();

    expect(provider.updateTaskCalls, 1);
    expect(provider.lastTaskClearDueDate, isTrue);
    expect(provider.lastTaskDueDate, isNull);
  });

  testWidgets('decision quick action can postpone due date by 7 days',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final base = DateTime.now().add(const Duration(days: 3));
    final provider = _FakeRoomProvider(
      fakeDecisions: [_decision(id: 'd-post', title: 'Planifier la demo')],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 72,
        criticalCount: 0,
        warningCount: 1,
        overdueTasks: 0,
        dueSoonTasks: 0,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 0,
        dueSoonDecisions: 1,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 decision a echeance courte.'],
        focusItems: [
          ExecutionPulseFocusItem(
            kind: 'decision',
            itemId: 'd-post',
            severity: 'warning',
            title: 'Planifier la demo',
            status: 'approved',
            ownerName: 'Alice',
            dueDate: base,
            subtitle: 'Demo planifiee • Alice',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gerer l echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reporter +7 jours'));
    await tester.pumpAndSettle();

    expect(provider.updateDecisionCalls, 1);
    expect(provider.lastDecisionDueDate, isNotNull);
    expect(
      DateUtils.dateOnly(provider.lastDecisionDueDate!),
      DateUtils.dateOnly(base.add(const Duration(days: 7))),
    );
  });

  testWidgets('task quick action can postpone due date by 7 days',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final base = DateTime.now().add(const Duration(days: 5));
    final provider = _FakeRoomProvider(
      fakeTasks: [
        _task(
          id: 't-post',
          title: 'Preparer le rapport final',
          status: 'in_progress',
          ownerName: 'Lina',
          dueDate: base,
        ),
      ],
      fakeExecutionPulse: ExecutionPulse(
        generatedAt: _now,
        status: 'attention',
        score: 78,
        criticalCount: 0,
        warningCount: 1,
        overdueTasks: 0,
        dueSoonTasks: 1,
        blockedTasks: 0,
        unassignedTasks: 0,
        overdueDecisions: 0,
        dueSoonDecisions: 0,
        decisionsWithoutOwner: 0,
        staleReviewDecisions: 0,
        recommendations: const ['1 tache a echeance courte.'],
        focusItems: [
          ExecutionPulseFocusItem(
            kind: 'task',
            itemId: 't-post',
            severity: 'warning',
            title: 'Preparer le rapport final',
            status: 'in_progress',
            ownerName: 'Lina',
            dueDate: base,
            subtitle: 'Tache planifiee • Lina',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Gerer l echeance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reporter +7 jours'));
    await tester.pumpAndSettle();

    expect(provider.updateTaskCalls, 1);
    expect(provider.lastTaskDueDate, isNotNull);
    expect(
      DateUtils.dateOnly(provider.lastTaskDueDate!),
      DateUtils.dateOnly(base.add(const Duration(days: 7))),
    );
  });
}
