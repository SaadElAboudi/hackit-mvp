import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/room.dart';
import '../providers/room_provider.dart';
import '../services/room_service.dart';

/// Full-screen canvas view for a RoomArtifact.
/// Supports version history switching and IA revision launching.
class CanvasScreen extends StatefulWidget {
  final String roomId;
  final String artifactId;
  final String? initialTitle;

  const CanvasScreen({
    super.key,
    required this.roomId,
    required this.artifactId,
    this.initialTitle,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  bool _loading = true;
  bool _busyAction = false;
  String? _error;
  RoomArtifact? _artifact;
  List<ArtifactVersion> _versions = [];
  ArtifactVersion? _selectedVersion;
  bool _showVersions = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = roomService;
      final artifacts = await svc.listArtifacts(widget.roomId);
      _artifact = artifacts.firstWhere(
        (a) => a.id == widget.artifactId,
        orElse: () => throw Exception('Artefact introuvable'),
      );
      _versions =
          await svc.fetchArtifactVersions(widget.roomId, widget.artifactId);
      if (_versions.isNotEmpty) {
        _selectedVersion = _versions.firstWhere(
          (v) => v.id == _artifact!.currentVersionId,
          orElse: () => _versions.last,
        );
      } else if (_artifact!.currentVersion != null) {
        _selectedVersion = _artifact!.currentVersion;
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showReviseDialog() async {
    if (_artifact == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Réviser "${_artifact!.title}"'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText:
                'Ex: ajoute un plan d\'action, simplifie le langage, prépare la v2 client…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
            child: const Text('Lancer la révision'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final success = await context
          .read<RoomProvider>()
          .reviseArtifact(_artifact!.id, ctrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? 'Révision IA lancée — la nouvelle version apparaîtra bientôt'
            : 'Impossible de lancer la révision'),
      ));
      if (success) _load();
    }
  }

  void _copyContent() {
    final content = _selectedVersion?.content ?? '';
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Contenu copié'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _approveSelectedVersion() async {
    final artifact = _artifact;
    final version = _selectedVersion;
    if (artifact == null || version == null) return;
    setState(() => _busyAction = true);
    try {
      final updated = await roomService.approveArtifactVersion(
        widget.roomId,
        artifact.id,
        version.id,
      );
      await _load();
      if (!mounted) return;
      setState(() {
        _selectedVersion = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Version validée ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _showAddCommentDialog() async {
    final artifact = _artifact;
    final version = _selectedVersion;
    if (artifact == null || version == null) return;

    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Commenter v${version.number}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Ex: Ajouter un cas d\'usage enterprise section 3',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyAction = true);
    try {
      final updated = await roomService.commentArtifactVersion(
        widget.roomId,
        artifact.id,
        version.id,
        content: ctrl.text.trim(),
      );
      await _load();
      if (!mounted) return;
      setState(() {
        _selectedVersion = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commentaire ajouté')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _artifact?.title ?? widget.initialTitle ?? 'Canvas';
    final versionCount = _versions.length;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
              if (_artifact != null)
                Text(
                  '${_artifact!.kind} • $versionCount version${versionCount != 1 ? 's' : ''}',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurface.withOpacity(0.55)),
                ),
            ],
          ),
        ),
        actions: [
          if (versionCount > 1)
            IconButton(
              icon: Icon(_showVersions
                  ? Icons.layers_clear_rounded
                  : Icons.layers_rounded),
              tooltip: 'Historique des versions',
              onPressed: () => setState(() => _showVersions = !_showVersions),
            ),
          IconButton(
            icon: const Icon(Icons.comment_outlined),
            tooltip: 'Commenter la version',
            onPressed: _busyAction || _selectedVersion == null
                ? null
                : _showAddCommentDialog,
          ),
          IconButton(
            icon: const Icon(Icons.verified_rounded),
            tooltip: 'Valider cette version',
            onPressed: _busyAction ||
                    _selectedVersion == null ||
                    _selectedVersion!.status == 'approved'
                ? null
                : _approveSelectedVersion,
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copier le contenu',
            onPressed: _copyContent,
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high_rounded),
            tooltip: 'Réviser avec IA',
            onPressed: _artifact != null ? _showReviseDialog : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(error: _error!, onRetry: _load)
              : LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  if (wide && _showVersions && _versions.length > 1) {
                    return Row(
                      children: [
                        Expanded(
                          child: _ContentView(
                            version: _selectedVersion,
                            onAddComment: _showAddCommentDialog,
                          ),
                        ),
                        _VersionsPanel(
                          versions: _versions,
                          selectedId: _selectedVersion?.id,
                          onSelect: (v) => setState(() => _selectedVersion = v),
                        ),
                      ],
                    );
                  }
                  return _ContentView(
                    version: _selectedVersion,
                    onAddComment: _showAddCommentDialog,
                  );
                }),
      floatingActionButton: _artifact == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showReviseDialog,
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Réviser avec IA'),
            ),
      bottomSheet: !_showVersions ||
              _versions.length < 2 ||
              MediaQuery.of(context).size.width >= 900
          ? null
          : _VersionsBottomBar(
              versions: _versions,
              selectedId: _selectedVersion?.id,
              onSelect: (v) => setState(() => _selectedVersion = v),
            ),
    );
  }
}

// ── Content view ──────────────────────────────────────────────────────────────

class _ContentView extends StatelessWidget {
  final ArtifactVersion? version;
  final VoidCallback? onAddComment;

  const _ContentView({this.version, this.onAddComment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (version == null) {
      return Center(
        child: Text(
          'Aucun contenu disponible.',
          style: TextStyle(color: scheme.onSurface.withOpacity(0.4)),
        ),
      );
    }
    return Column(
      children: [
        // Version status strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          color: version!.status == 'approved'
              ? Colors.green.withOpacity(0.1)
              : scheme.surfaceContainerLow,
          child: Row(
            children: [
              Icon(
                version!.status == 'approved'
                    ? Icons.check_circle_outline_rounded
                    : Icons.edit_note_rounded,
                size: 15,
                color: version!.status == 'approved'
                    ? Colors.green
                    : scheme.onSurface.withOpacity(0.45),
              ),
              const SizedBox(width: 6),
              Text(
                'v${version!.number} · ${version!.status} · ${_fmt(version!.createdAt)}',
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurface.withOpacity(0.55)),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  version!.content,
                  style: const TextStyle(fontSize: 14.5, height: 1.7),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      'Commentaires (${version!.comments.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: onAddComment,
                      icon: const Icon(Icons.add_comment_outlined, size: 16),
                      label: const Text('Ajouter'),
                    ),
                  ],
                ),
                if (version!.comments.isEmpty)
                  Text(
                    'Aucun commentaire pour cette version.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withOpacity(0.5),
                    ),
                  )
                else
                  ...version!.comments.reversed.map((comment) {
                    final author = comment.authorName.isNotEmpty
                        ? comment.authorName
                        : 'Anonyme';
                    final text = comment.content;
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$author: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            TextSpan(
                              text: text,
                              style:
                                  const TextStyle(fontSize: 12, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ── Versions panel (desktop sidebar) ─────────────────────────────────────────

class _VersionsPanel extends StatelessWidget {
  final List<ArtifactVersion> versions;
  final String? selectedId;
  final void Function(ArtifactVersion) onSelect;

  const _VersionsPanel({
    required this.versions,
    this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant.withOpacity(0.35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'Versions',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: versions.length,
              itemBuilder: (ctx, i) {
                // Show newest first
                final v = versions[versions.length - 1 - i];
                final selected = v.id == selectedId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: scheme.secondaryContainer.withOpacity(0.4),
                  leading: CircleAvatar(
                    radius: 13,
                    backgroundColor: selected
                        ? scheme.secondary
                        : scheme.surfaceContainerHigh,
                    foregroundColor:
                        selected ? scheme.onSecondary : scheme.onSurface,
                    child: Text(
                      'v${v.number}',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                  title: Text(
                    v.status == 'approved' ? 'Approuvée ✓' : 'Brouillon',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    '${v.createdAt.day}/${v.createdAt.month}/${v.createdAt.year}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  onTap: () => onSelect(v),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Versions bottom bar (mobile) ──────────────────────────────────────────────

class _VersionsBottomBar extends StatelessWidget {
  final List<ArtifactVersion> versions;
  final String? selectedId;
  final void Function(ArtifactVersion) onSelect;

  const _VersionsBottomBar({
    required this.versions,
    this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      color: scheme.surfaceContainerLow,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: versions.length,
        itemBuilder: (ctx, i) {
          final v = versions[versions.length - 1 - i];
          final selected = v.id == selectedId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              label: Text('v${v.number}'),
              onSelected: (_) => onSelect(v),
            ),
          );
        },
      ),
    );
  }
}

// ── Error body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.error, size: 40),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
