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
    })..artifacts = [artifact];

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
    })..artifacts = [artifact];

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
    })..artifacts = [artifact];

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
    })..artifacts = [artifact];

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
    })..artifacts = [artifact];

    await tester.pumpWidget(
      _wrap(ArtifactReviewScreen(artifact: artifact), provider),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aucune version'), findsOneWidget);
    expect(find.text('Soumettre en revue'), findsOneWidget);
  });
}
