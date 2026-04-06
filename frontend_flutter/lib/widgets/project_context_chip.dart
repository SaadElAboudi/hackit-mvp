import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/project_provider.dart';
import '../models/project.dart';

/// Tapping this chip opens a bottom sheet to create/edit/clear the active project.
class ProjectContextChip extends StatelessWidget {
  const ProjectContextChip({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final project = provider.activeProject;
    final scheme = Theme.of(context).colorScheme;

    if (project == null) {
      return TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          foregroundColor: scheme.onSurface.withValues(alpha: 0.55),
        ),
        icon: const Icon(Icons.work_outline_rounded, size: 16),
        label: const Text('Projet client', style: TextStyle(fontSize: 12)),
        onPressed: () => _showSheet(context, null),
      );
    }

    return GestureDetector(
      onTap: () => _showSheet(context, project),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: scheme.primary.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_rounded, size: 13, color: scheme.primary),
            const SizedBox(width: 5),
            Text(
              project.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
            if ((project.sector ?? '').isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                '· ${project.sector}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.65),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, ClientProject? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProjectSheet(existing: existing),
    );
  }
}

class _ProjectSheet extends StatefulWidget {
  final ClientProject? existing;
  const _ProjectSheet({this.existing});

  @override
  State<_ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends State<_ProjectSheet> {
  late final TextEditingController _name;
  late final TextEditingController _sector;
  late final TextEditingController _teamSize;
  late final TextEditingController _challenge;
  late final TextEditingController _budget;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _sector = TextEditingController(text: p?.sector ?? '');
    _teamSize = TextEditingController(text: p?.teamSize ?? '');
    _challenge = TextEditingController(text: p?.mainChallenge ?? '');
    _budget = TextEditingController(text: p?.budget ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _sector.dispose();
    _teamSize.dispose();
    _challenge.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.read<ProjectProvider>();
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.work_rounded, color: scheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                isEdit ? 'Modifier le projet' : 'Nouveau projet client',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ce contexte sera injecté dans toutes tes requêtes.',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          _field('Nom du projet *', _name, hint: 'Ex: Transformation digitale Acme'),
          const SizedBox(height: 12),
          _field('Secteur', _sector, hint: 'Ex: Fintech, Retail, Industrie'),
          const SizedBox(height: 12),
          _field('Taille équipe / entreprise', _teamSize, hint: 'Ex: 50 personnes, Series B'),
          const SizedBox(height: 12),
          _field('Enjeu principal', _challenge, hint: 'Ex: Réduire le churn de 30% en 6 mois', maxLines: 2),
          const SizedBox(height: 12),
          _field('Budget / contrainte', _budget, hint: 'Ex: 200k€, Q3 deadline'),
          const SizedBox(height: 24),
          Row(
            children: [
              if (isEdit)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () async {
                    await provider.clearProject();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Effacer le projet'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () async {
                        if (isEdit) {
                          await provider.setProject(
                            widget.existing!.copyWith(
                              name: _name.text,
                              sector: _sector.text,
                              teamSize: _teamSize.text,
                              mainChallenge: _challenge.text,
                              budget: _budget.text,
                            ),
                          );
                        } else {
                          await provider.createProject(
                            name: _name.text,
                            sector: _sector.text,
                            teamSize: _teamSize.text,
                            mainChallenge: _challenge.text,
                            budget: _budget.text,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                child: Text(isEdit ? 'Enregistrer' : 'Créer le projet'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, int maxLines = 1}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.35), fontSize: 13),
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}
