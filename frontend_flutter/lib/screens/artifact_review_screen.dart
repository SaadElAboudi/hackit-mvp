import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/room.dart';
import '../providers/room_provider.dart';

/// Full-screen artifact review panel.
/// Shows version history, comments timeline and workflow actions.
class ArtifactReviewScreen extends StatefulWidget {
  final RoomArtifact artifact;

  const ArtifactReviewScreen({super.key, required this.artifact});

  @override
  State<ArtifactReviewScreen> createState() => _ArtifactReviewScreenState();
}

class _ArtifactReviewScreenState extends State<ArtifactReviewScreen> {
  late RoomArtifact _artifact;
  List<ArtifactVersion> _versions = [];
  ArtifactVersion? _selected;
  bool _loadingVersions = true;
  final _commentCtrl = TextEditingController();
  final _rejectCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _artifact = widget.artifact;
    _loadVersions();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _rejectCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    final prov = context.read<RoomProvider>();
    final vs = await prov.fetchVersions(_artifact.id);
    if (!mounted) return;
    setState(() {
      _versions = vs;
      _selected = vs.isNotEmpty ? vs.last : null;
      _loadingVersions = false;
    });
  }

  Color _statusColor(String status, ColorScheme cs) => switch (status) {
        'draft' => cs.outline,
        'review' => const Color(0xFFB45309),
        'validated' => cs.primary,
        'archived' => cs.outlineVariant,
        _ => cs.outline,
      };

  Color _statusBg(String status, ColorScheme cs) => switch (status) {
        'draft' => cs.surfaceContainerHighest,
        'review' => const Color(0xFFFEF3C7),
        'validated' => cs.primaryContainer,
        'archived' => cs.surfaceContainerLow,
        _ => cs.surfaceContainerHighest,
      };

  String _statusLabel(String status) => switch (status) {
        'draft' => 'Brouillon',
        'review' => 'En revue',
        'validated' => 'Validé',
        'archived' => 'Archivé',
        _ => status,
      };

  Future<void> _changeStatus(String newStatus) async {
    setState(() => _submitting = true);
    final prov = context.read<RoomProvider>();
    final ok = await prov.updateArtifactStatus(_artifact.id, newStatus);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      final updated = prov.artifacts.firstWhere(
        (a) => a.id == _artifact.id,
        orElse: () => _artifact,
      );
      setState(() => _artifact = updated);
    } else if (prov.actionError != null) {
      _showError(prov.actionError!);
    }
  }

  Future<void> _approve() async {
    if (_selected == null) return;
    setState(() => _submitting = true);
    final prov = context.read<RoomProvider>();
    final ok = await prov.approveVersion(_artifact.id, _selected!.id);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      _showSnack('Version approuvée ✓');
      await _loadVersions();
    } else if (prov.actionError != null) {
      _showError(prov.actionError!);
    }
  }

  Future<void> _reject() async {
    if (_selected == null) return;
    final reason = await _showRejectDialog();
    if (reason == null || !mounted) return;
    setState(() => _submitting = true);
    final prov = context.read<RoomProvider>();
    final ok = await prov.rejectVersion(_artifact.id, _selected!.id,
        reason: reason);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      _showSnack('Version refusée');
      await _loadVersions();
    } else if (prov.actionError != null) {
      _showError(prov.actionError!);
    }
  }

  Future<String?> _showRejectDialog() async {
    _rejectCtrl.clear();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motif du refus'),
        content: TextField(
          controller: _rejectCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Expliquez pourquoi cette version est refusée…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _rejectCtrl.text.trim()),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _selected == null) return;
    setState(() => _submitting = true);
    final prov = context.read<RoomProvider>();
    final updated =
        await prov.addComment(_artifact.id, _selected!.id, text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (updated != null) {
      _commentCtrl.clear();
      setState(() {
        final idx = _versions.indexWhere((v) => v.id == updated.id);
        if (idx >= 0) {
          _versions[idx] = updated;
          _selected = updated;
        }
      });
    } else if (prov.actionError != null) {
      _showError(prov.actionError!);
    }
  }

  Future<void> _toggleResolve(ArtifactComment comment) async {
    if (_selected == null) return;
    final prov = context.read<RoomProvider>();
    final updated = await prov.resolveComment(
      _artifact.id,
      _selected!.id,
      comment.id,
      resolved: !comment.resolved,
    );
    if (!mounted || updated == null) return;
    setState(() {
      final idx = _versions.indexWhere((v) => v.id == updated.id);
      if (idx >= 0) {
        _versions[idx] = updated;
        _selected = updated;
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = _artifact.status;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                _artifact.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _KindBadge(kind: _artifact.kind, cs: cs),
            const SizedBox(width: 8),
            _StatusChip(
              label: _statusLabel(status),
              fg: _statusColor(status, cs),
              bg: _statusBg(status, cs),
            ),
          ],
        ),
      ),
      body: _loadingVersions
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _VersionSelector(
                  versions: _versions,
                  selected: _selected,
                  onChanged: (v) => setState(() => _selected = v),
                  cs: cs,
                  tt: tt,
                ),
                const Divider(height: 1),
                Expanded(
                  child: _selected == null
                      ? Center(
                          child: Text('Aucune version',
                              style: tt.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        )
                      : _ReviewBody(
                          version: _selected!,
                          onToggleResolve: _toggleResolve,
                          commentCtrl: _commentCtrl,
                          onSubmitComment: _submitComment,
                          submitting: _submitting,
                          cs: cs,
                          tt: tt,
                        ),
                ),
                const Divider(height: 1),
                _ActionBar(
                  status: status,
                  submitting: _submitting,
                  onSubmitReview: () => _changeStatus('review'),
                  onApprove: _approve,
                  onReject: _reject,
                  onArchive: () => _changeStatus('archived'),
                ),
              ],
            ),
    );
  }
}

// ─── Version selector ─────────────────────────────────────────────────────────

class _VersionSelector extends StatelessWidget {
  final List<ArtifactVersion> versions;
  final ArtifactVersion? selected;
  final ValueChanged<ArtifactVersion?> onChanged;
  final ColorScheme cs;
  final TextTheme tt;

  const _VersionSelector({
    required this.versions,
    required this.selected,
    required this.onChanged,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    if (versions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<ArtifactVersion>(
        initialValue: selected,
        decoration: InputDecoration(
          labelText: 'Version',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: versions.map((v) {
          final label = 'v${v.number}'
              '${v.changeSummary.isNotEmpty ? ' — ${v.changeSummary}' : ''}'
              '${v.authorName.isNotEmpty ? ' (${v.authorName})' : ''}';
          return DropdownMenuItem(
            value: v,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium,
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Review body ──────────────────────────────────────────────────────────────

class _ReviewBody extends StatelessWidget {
  final ArtifactVersion version;
  final ValueChanged<ArtifactComment> onToggleResolve;
  final TextEditingController commentCtrl;
  final VoidCallback onSubmitComment;
  final bool submitting;
  final ColorScheme cs;
  final TextTheme tt;

  const _ReviewBody({
    required this.version,
    required this.onToggleResolve,
    required this.commentCtrl,
    required this.onSubmitComment,
    required this.submitting,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Content preview
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contenu', style: tt.labelLarge),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: SelectableText(
                    version.content,
                    style: tt.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Comments header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Text('Commentaires', style: tt.labelLarge),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${version.comments.length}',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Comments timeline
        version.comments.isEmpty
            ? SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Aucun commentaire pour cette version.',
                    style:
                        tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _CommentTile(
                    comment: version.comments[i],
                    onToggleResolve: onToggleResolve,
                    cs: cs,
                    tt: tt,
                  ),
                  childCount: version.comments.length,
                ),
              ),

        // Add comment input
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: commentCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Ajouter un commentaire…',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (_) => onSubmitComment(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: submitting ? null : onSubmitComment,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 18),
                  label: const Text('Envoyer'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Comment tile ─────────────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final ArtifactComment comment;
  final ValueChanged<ArtifactComment> onToggleResolve;
  final ColorScheme cs;
  final TextTheme tt;

  const _CommentTile({
    required this.comment,
    required this.onToggleResolve,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = comment.resolved;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: resolved ? cs.primary : cs.outline,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: resolved
                    ? cs.surfaceContainerLow
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: resolved ? cs.outlineVariant : cs.outline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        comment.authorName.isNotEmpty
                            ? comment.authorName
                            : 'Anonyme',
                        style: tt.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        _timeAgo(comment.createdAt),
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(width: 4),
                      if (resolved)
                        Tooltip(
                          message: 'Résolu',
                          child: Icon(Icons.check_circle,
                              size: 14, color: cs.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(comment.content, style: tt.bodySmall),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => onToggleResolve(comment),
                      icon: Icon(
                        resolved
                            ? Icons.undo_rounded
                            : Icons.check_circle_outline,
                        size: 14,
                      ),
                      label:
                          Text(resolved ? 'Rouvrir' : 'Résoudre',
                              style: tt.labelSmall),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'maintenant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }
}

// ─── Action bar ───────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final String status;
  final bool submitting;
  final VoidCallback onSubmitReview;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onArchive;

  const _ActionBar({
    required this.status,
    required this.submitting,
    required this.onSubmitReview,
    required this.onApprove,
    required this.onReject,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = <Widget>[];

    if (status == 'draft') {
      actions.add(
        FilledButton.icon(
          onPressed: submitting ? null : onSubmitReview,
          icon: const Icon(Icons.rate_review_outlined, size: 18),
          label: const Text('Soumettre en revue'),
        ),
      );
    }

    if (status == 'review') {
      actions.addAll([
        FilledButton.icon(
          onPressed: submitting ? null : onApprove,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Approuver'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: submitting ? null : onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.error,
            side: BorderSide(color: cs.error),
          ),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Refuser'),
        ),
      ]);
    }

    if (status == 'validated') {
      actions.add(
        OutlinedButton.icon(
          onPressed: submitting ? null : onArchive,
          icon: const Icon(Icons.archive_outlined, size: 18),
          label: const Text('Archiver'),
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: actions,
        ),
      ),
    );
  }
}

// ─── Small badges ─────────────────────────────────────────────────────────────

class _KindBadge extends StatelessWidget {
  final String kind;
  final ColorScheme cs;

  const _KindBadge({required this.kind, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kind,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSecondaryContainer,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const _StatusChip(
      {required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
