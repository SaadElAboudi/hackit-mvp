import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hackit_mvp_flutter/models/room.dart';
import 'package:hackit_mvp_flutter/providers/room_provider.dart';
import 'package:hackit_mvp_flutter/screens/artifact_review_screen.dart';

class _FakeReviewProvider extends RoomProvider {
  _FakeReviewProvider(this.versionsByArtifact);

  final Map<String, List<ArtifactVersion>> versionsByArtifact;
  String? lastStatusUpdate;
  String? lastAddedComment;
  bool lastApprovedVersion = false;
  bool lastRejectedVersion = false;
  String? lastRejectReason;
  String? lastResolvedCommentId;
  bool lastResolvedValue = false;

  @override
  Future<List<ArtifactVersion>> fetchVersions(String artifactId) async {
    return versionsByArtifact[artifactId] ?? const <ArtifactVersion>[];
  }

  @override
  Future<bool> updateArtifactStatus(String artifactId, String status) async {
    lastStatusUpdate = status;
    final idx = artifacts.indexWhere((a) => a.id == artifactId);
    if (idx >= 0) {
      final current = artifacts[idx];
      artifacts[idx] = RoomArtifact(
        id: current.id,
        roomId: current.roomId,
        title: current.title,
        kind: current.kind,
        status: status,
        currentVersionId: current.currentVersionId,
        currentVersion: current.currentVersion,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
    }
    return true;
  }

  @override
  Future<ArtifactVersion?> addComment(
    String artifactId,
    String versionId,
    String content, {
    String? displayName,
  }) async {
    lastAddedComment = content;
    final versions = versionsByArtifact[artifactId];
    if (versions == null) return null;
    final vIdx = versions.indexWhere((v) => v.id == versionId);
    if (vIdx < 0) return null;
    final v = versions[vIdx];
    final newComment = ArtifactComment(
      id: 'c-new',
      content: content,
      authorId: 'user-1',
      authorName: displayName ?? 'Alice',
      resolved: false,
      createdAt: DateTime.now(),
    );
    final updated = ArtifactVersion(
      id: v.id,
      artifactId: v.artifactId,
      number: v.number,
      content: v.content,
      status: v.status,
      comments: [...v.comments, newComment],
      createdAt: v.createdAt,
      changeSummary: v.changeSummary,
      authorName: v.authorName,
    );
    versions[vIdx] = updated;
    return updated;
  }

  @override
  Future<bool> approveVersion(String artifactId, String versionId) async {
    lastApprovedVersion = true;
    return true;
  }

  @override
  Future<bool> rejectVersion(
    String artifactId,
    String versionId, {
    String reason = '',
  }) async {
    lastRejectedVersion = true;
    lastRejectReason = reason;
    return true;
  }

  @override
  Future<ArtifactVersion?> resolveComment(
    String artifactId,
    String versionId,
    String commentId, {
    bool resolved = true,
  }) async {
    lastResolvedCommentId = commentId;
    lastResolvedValue = resolved;
    final versions = versionsByArtifact[artifactId];
    if (versions == null) return null;
    final vIdx = versions.indexWhere((v) => v.id == versionId);
    if (vIdx < 0) return null;
    final v = versions[vIdx];
    final cIdx = v.comments.indexWhere((c) => c.id == commentId);
    if (cIdx < 0) return null;
    final updated = ArtifactVersion(
      id: v.id,
      artifactId: v.artifactId,
      number: v.number,
      content: v.content,
      status: v.status,
      comments: List<ArtifactComment>.from(v.comments)
        ..[cIdx] = ArtifactComment(
          id: commentId,
          content: v.comments[cIdx].content,
          authorId: v.comments[cIdx].authorId,
          authorName: v.comments[cIdx].authorName,
          resolved: resolved,
          createdAt: v.comments[cIdx].createdAt,
        ),
      createdAt: v.createdAt,
      changeSummary: v.changeSummary,
      authorName: v.authorName,
    );
    versions[vIdx] = updated;
    return updated;
  }
}

RoomArtifact _artifact({required String status}) {
  final now = DateTime.now().toIso8601String();
  return RoomArtifact.fromJson({
    'id': 'artifact-1',
    'roomId': 'room-1',
    'title': 'Plan sprint',
    'kind': 'document',
    'status': status,
    'updatedAt': now,
  });
}

ArtifactVersion _version({
  required String id,
  required int number,
  required String content,
  required String summary,
  String status = 'draft',
}) {
  return ArtifactVersion.fromJson({
    'id': id,
    'artifactId': 'artifact-1',
    'number': number,
    'content': content,
    'status': status,
    'changeSummary': summary,
    'authorName': 'Alice',
    'createdAt': DateTime.now().toIso8601String(),
    'comments': [],
  });
}

Widget _wrap(Widget child, RoomProvider provider) {
  return ChangeNotifierProvider<RoomProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('draft artifact shows submit review action and updates status',
      (tester) async {
    final artifact = _artifact(status: 'draft');
    final provider = _FakeReviewProvider({
      artifact.id: [
        _version(
          id: 'v1',
          number: 1,
          content: 'Contenu version 1',
          summary: 'Initial',
        ),
      ],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    expect(find.text('Soumettre en revue'), findsOneWidget);

    await tester.tap(find.text('Soumettre en revue'));
    await tester.pumpAndSettle();

    expect(provider.lastStatusUpdate, 'review');
    expect(find.text('En revue'), findsOneWidget);
  });

  testWidgets('review artifact shows approve and reject actions',
      (tester) async {
    final artifact = _artifact(status: 'review');
    final provider = _FakeReviewProvider({
      artifact.id: [
        _version(
          id: 'v1',
          number: 1,
          content: 'Contenu version 1',
          summary: 'Initial',
          status: 'review',
        ),
      ],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approuver'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    expect(find.text('Soumettre en revue'), findsNothing);
  });

  testWidgets('version selector switches displayed content', (tester) async {
    final artifact = _artifact(status: 'draft');
    final provider = _FakeReviewProvider({
      artifact.id: [
        _version(
          id: 'v1',
          number: 1,
          content: 'Contenu version 1',
          summary: 'Initial',
        ),
        _version(
          id: 'v2',
          number: 2,
          content: 'Contenu version 2',
          summary: 'Ajouts',
        ),
      ],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    // The latest version is selected by default.
    expect(find.text('Contenu version 2'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<ArtifactVersion>));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('v1').last);
    await tester.pumpAndSettle();

    expect(find.text('Contenu version 1'), findsOneWidget);
  });

  testWidgets('validated artifact shows archive action only', (tester) async {
    final artifact = _artifact(status: 'validated');
    final provider = _FakeReviewProvider({
      artifact.id: [
        _version(
          id: 'v1',
          number: 1,
          content: 'Contenu valide',
          summary: 'Finale',
          status: 'validated',
        ),
      ],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archiver'), findsOneWidget);
    expect(find.text('Approuver'), findsNothing);
    expect(find.text('Refuser'), findsNothing);
    expect(find.text('Soumettre en revue'), findsNothing);
  });

  testWidgets('shows empty-version fallback when no version exists',
      (tester) async {
    final artifact = _artifact(status: 'draft');
    final provider = _FakeReviewProvider({
      artifact.id: const <ArtifactVersion>[],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aucune version'), findsOneWidget);
    expect(find.text('Soumettre en revue'), findsOneWidget);
  });

  testWidgets('submitting a comment appends it to the version', (tester) async {
    final artifact = _artifact(status: 'review');
    final provider = _FakeReviewProvider({
      artifact.id: [
        _version(
          id: 'v1',
          number: 1,
          content: 'Contenu initial',
          summary: 'Initial',
          status: 'review',
        ),
      ],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    // The comment count badge shows 0 initially.
    expect(find.text('0'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ajouter un commentaire…'),
      'Mon commentaire test',
    );
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();

    expect(provider.lastAddedComment, 'Mon commentaire test');
    // After fake addComment returns updated version with 1 comment,
    // the badge should update to 1.
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('reject dialog collects reason and calls rejectVersion',
      (tester) async {
    final artifact = _artifact(status: 'review');
    final provider = _FakeReviewProvider({
      artifact.id: [
        _version(
          id: 'v1',
          number: 1,
          content: 'Contenu a refuser',
          summary: 'Initial',
          status: 'review',
        ),
      ],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();

    // Dialog should appear with a text field.
    expect(find.text('Motif du refus'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'Contenu insuffisant',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
    await tester.pumpAndSettle();

    expect(provider.lastRejectedVersion, isTrue);
    expect(provider.lastRejectReason, 'Contenu insuffisant');
  });

  testWidgets('approving a version calls approveVersion and shows snack',
      (tester) async {
    final artifact = _artifact(status: 'review');
    final provider = _FakeReviewProvider({
      artifact.id: [
        _version(
          id: 'v1',
          number: 1,
          content: 'Contenu valide',
          summary: 'Finale',
          status: 'review',
        ),
      ],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approuver'));
    await tester.pumpAndSettle();

    expect(provider.lastApprovedVersion, isTrue);
    expect(find.text('Version approuvée ✓'), findsOneWidget);
  });

  testWidgets('resolving a comment updates its state', (tester) async {
    final artifact = _artifact(status: 'review');
    final comment = ArtifactComment(
      id: 'c-1',
      content: 'A corriger',
      authorId: 'user-1',
      authorName: 'Bob',
      resolved: false,
      createdAt: DateTime.now(),
    );
    final versionWithComment = ArtifactVersion(
      id: 'v1',
      artifactId: artifact.id,
      number: 1,
      content: 'Contenu avec commentaire',
      status: 'review',
      comments: [comment],
      createdAt: DateTime.now(),
      changeSummary: 'Initial',
      authorName: 'Alice',
    );
    final provider = _FakeReviewProvider({
      artifact.id: [versionWithComment],
    })
      ..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    expect(find.text('A corriger'), findsOneWidget);
    await tester.tap(find.text('Résoudre'));
    await tester.pumpAndSettle();

    expect(provider.lastResolvedCommentId, 'c-1');
    expect(provider.lastResolvedValue, isTrue);
  });
}
