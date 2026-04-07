import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/collab.dart';
import '../providers/collab_provider.dart';
import '../core/responsive/size_config.dart';
import 'collab_thread_screen.dart';

/// Lists all collaborative projects the user belongs to.
/// Entry-point for the "Projets" tab.
class CollabProjectsScreen extends StatefulWidget {
  const CollabProjectsScreen({super.key});

  @override
  State<CollabProjectsScreen> createState() => _CollabProjectsScreenState();
}

class _CollabProjectsScreenState extends State<CollabProjectsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CollabProvider>().loadProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        title: Text(
          'Projets',
          style: TextStyle(
            fontSize: SizeConfig.adaptiveFontSize(17),
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rafraîchir',
            onPressed: () => context.read<CollabProvider>().loadProjects(),
          ),
        ],
      ),
      body: Consumer<CollabProvider>(
        builder: (context, prov, _) {
          if (prov.projectsState == CollabLoadState.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (prov.projectsState == CollabLoadState.error) {
            return _ErrorView(
              message: prov.projectsError ?? 'Erreur',
              onRetry: () => prov.loadProjects(),
            );
          }
          if (prov.projects.isEmpty) {
            return _EmptyState(
              onCreateTap: () => _showCreateSheet(context),
              onJoinTap: () => _showJoinSheet(context),
            );
          }
          return RefreshIndicator(
            onRefresh: prov.loadProjects,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: prov.projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) =>
                  _ProjectCard(project: prov.projects[i]),
            ),
          );
        },
      ),
      floatingActionButton: _Fab(
        onCreate: () => _showCreateSheet(context),
        onJoin: () => _showJoinSheet(context),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateProjectSheet(),
    );
  }

  void _showJoinSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _JoinProjectSheet(),
    );
  }
}

// ─── Project card ─────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final CollabProject project;
  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProject(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      project.title.isNotEmpty
                          ? project.title[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          style: TextStyle(
                            fontSize: SizeConfig.adaptiveFontSize(14),
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (project.description.isNotEmpty)
                          Text(
                            project.description,
                            style: TextStyle(
                              fontSize: SizeConfig.adaptiveFontSize(12),
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: scheme.onSurface.withValues(alpha: 0.3)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Chip(
                    icon: Icons.group_rounded,
                    label:
                        '${project.memberCount} membre${project.memberCount > 1 ? 's' : ''}',
                    scheme: scheme,
                  ),
                  const SizedBox(width: 8),
                  if (project.isPublic)
                    _Chip(
                      icon: Icons.public_rounded,
                      label: 'Public',
                      scheme: scheme,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProject(BuildContext context) {
    context.read<CollabProvider>().openProject(project.slug);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<CollabProvider>(),
          child: CollabThreadListScreen(project: project),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;
  const _Chip({required this.icon, required this.label, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: scheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Thread list inside a project ─────────────────────────────────────────────

class CollabThreadListScreen extends StatelessWidget {
  final CollabProject project;
  const CollabThreadListScreen({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        title: Text(
          project.title,
          style: TextStyle(
            fontSize: SizeConfig.adaptiveFontSize(16),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (project.inviteToken != null)
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'Copier le lien d\'invitation',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: project.inviteUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Lien copié dans le presse-papiers')),
                );
              },
            ),
        ],
      ),
      body: Consumer<CollabProvider>(
        builder: (context, prov, _) {
          if (prov.threadsState == CollabLoadState.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (prov.threads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forum_outlined,
                        size: 48,
                        color: scheme.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text(
                      'Aucune conversation',
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _showNewThreadSheet(context, prov),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Nouvelle conversation'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: prov.threads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final t = prov.threads[i];
              return _ThreadTile(
                thread: t,
                project: project,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showNewThreadSheet(context, context.read<CollabProvider>()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle conversation'),
      ),
    );
  }

  void _showNewThreadSheet(BuildContext ctx, CollabProvider prov) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _Sheet(
        title: 'Nouvelle conversation',
        child: Column(
          children: [
            _Input(
              controller: ctrl,
              hint: 'Titre (ex. Stratégie de lancement)',
              autofocus: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final title = ctrl.text.trim();
                  if (title.isEmpty) return;
                  Navigator.pop(ctx);
                  final thread = await prov.createThread(
                    project.slug,
                    title: title,
                  );
                  if (thread != null && ctx.mounted) {
                    Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: ctx.read<CollabProvider>(),
                        child: CollabThreadScreen(
                          project: project,
                          thread: thread,
                        ),
                      ),
                    ));
                  }
                },
                child: const Text('Créer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final CollabThread thread;
  final CollabProject project;
  const _ThreadTile({required this.thread, required this.project});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msgCount = thread.messages.length;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.read<CollabProvider>().openThread(project.slug, thread.id);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: context.read<CollabProvider>(),
              child: CollabThreadScreen(project: project, thread: thread),
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.forum_rounded,
                    size: 16, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      style: TextStyle(
                        fontSize: SizeConfig.adaptiveFontSize(13.5),
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      '$msgCount message${msgCount != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.25)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Create project sheet ─────────────────────────────────────────────────────

class _CreateProjectSheet extends StatefulWidget {
  const _CreateProjectSheet();

  @override
  State<_CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends State<_CreateProjectSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Nouveau projet',
      child: Column(
        children: [
          _Input(
              controller: _titleCtrl, hint: 'Nom du projet', autofocus: true),
          const SizedBox(height: 10),
          _Input(
              controller: _descCtrl,
              hint: 'Description (optionnelle)',
              maxLines: 2),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Créer le projet'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _loading = true);
    final p = await context.read<CollabProvider>().createProject(
          title: title,
          description: _descCtrl.text.trim(),
        );
    if (mounted) {
      Navigator.pop(context);
      if (p != null) {
        context.read<CollabProvider>().openProject(p.slug);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: context.read<CollabProvider>(),
            child: CollabThreadListScreen(project: p),
          ),
        ));
      }
    }
  }
}

// ─── Join project sheet ────────────────────────────────────────────────────────

class _JoinProjectSheet extends StatefulWidget {
  const _JoinProjectSheet();
  @override
  State<_JoinProjectSheet> createState() => _JoinProjectSheetState();
}

class _JoinProjectSheetState extends State<_JoinProjectSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: 'Rejoindre un projet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Input(
            controller: _ctrl,
            hint: 'Token ou lien d\'invitation',
            autofocus: true,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Rejoindre'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    // Extract token from a full URL if pasted
    final token =
        raw.contains('/join/') ? raw.split('/join/').last.trim() : raw;
    setState(() {
      _loading = true;
      _error = null;
    });
    final p = await context.read<CollabProvider>().joinByToken(token);
    if (mounted) {
      if (p == null) {
        setState(() {
          _error = 'Lien invalide ou expiré';
          _loading = false;
        });
      } else {
        Navigator.pop(context);
      }
    }
  }
}

// ─── Shared UI helpers ────────────────────────────────────────────────────────

class _Fab extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  const _Fab({required this.onCreate, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'join_fab',
          tooltip: 'Rejoindre',
          onPressed: onJoin,
          child: const Icon(Icons.link_rounded),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'create_fab',
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouveau projet'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  final VoidCallback onJoinTap;
  const _EmptyState({required this.onCreateTap, required this.onJoinTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspaces_outline,
                size: 56, color: scheme.onSurface.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(
              'Aucun projet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Créez un espace de travail partagé\nou rejoignez-en un avec un lien.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Créer un projet'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onJoinTap,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Rejoindre via lien'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: Colors.red),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;
  const _Sheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final int maxLines;
  const _Input({
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
