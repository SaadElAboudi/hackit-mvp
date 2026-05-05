import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/room.dart';
import '../providers/room_provider.dart';

/// OpsHub: Central operational dashboard for daily standups and decision-making.
/// Shows: execution pulse, feedback trends, recent exports, quick actions.
class OpsHubScreen extends StatefulWidget {
  const OpsHubScreen({super.key});

  @override
  State<OpsHubScreen> createState() => _OpsHubScreenState();
}

class _OpsHubScreenState extends State<OpsHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<RoomProvider>();
      if (prov.currentRoom != null) {
        prov.refreshExecutionPulse(silent: true);
        prov.loadFeedbackDigest(silent: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoomProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (prov.currentRoom == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Operations Hub')),
        body: Center(
          child: Text(
            'Selectionnez un channel pour voir le pulse operation',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operations Hub'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await prov.refreshExecutionPulse();
          await prov.loadFeedbackDigest();
        },
        child: CustomScrollView(
          slivers: [
            if (prov.executionPulse != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ExecutionPulseOverviewCard(
                    pulse: prov.executionPulse!,
                  ),
                ),
              ),
            if (prov.feedbackDigest != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _FeedbackInsightsCard(
                    digest: prov.feedbackDigest!,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _QuickActionsCard(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _RecentExportsCard(),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionPulseOverviewCard extends StatelessWidget {
  final ExecutionPulse pulse;

  const _ExecutionPulseOverviewCard({required this.pulse});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = _executionPulseColor(pulse.status, scheme);
    final statusLabel = _executionPulseLabel(pulse.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    Icon(Icons.monitor_heart_outlined, color: tone, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Execution Pulse',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tone,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${pulse.score}/100',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _OperationMetricBadge(
                label: 'En retard',
                count: pulse.criticalCount,
                severity: 'critical',
                icon: Icons.event_busy_outlined,
              ),
              _OperationMetricBadge(
                label: 'A attention',
                count: pulse.warningCount,
                severity: 'warning',
                icon: Icons.visibility_outlined,
              ),
              _OperationMetricBadge(
                label: 'Decisions',
                count: pulse.decisionsWithoutOwner,
                severity: 'info',
                icon: Icons.folder_outlined,
              ),
              _OperationMetricBadge(
                label: 'Taches',
                count: pulse.blockedTasks,
                severity: 'critical',
                icon: Icons.block_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OperationMetricBadge extends StatelessWidget {
  final String label;
  final int count;
  final String severity;
  final IconData icon;

  const _OperationMetricBadge({
    required this.label,
    required this.count,
    required this.severity,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = severity == 'critical'
        ? scheme.error
        : severity == 'warning'
            ? scheme.tertiary
            : scheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackInsightsCard extends StatelessWidget {
  final FeedbackDigest digest;

  const _FeedbackInsightsCard({required this.digest});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Feedback Trends',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pertinence: ${(digest.pertinentRate * 100).toStringAsFixed(0)}% ↑',
            style: TextStyle(
              fontSize: 13,
              color: digest.pertinentRate >= 0.65
                  ? scheme.tertiary
                  : scheme.onSurface.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (digest.topFrictionPatterns.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Top friction: ${digest.topFrictionPatterns.first}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.error.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (digest.topWinPatterns.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Top win: ${digest.topWinPatterns.first}',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF2E8B57),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prov = context.read<RoomProvider>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actions Rapides',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Decision pack ouvert'),
                    ),
                  );
                },
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Open Decision Pack'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (prov.currentRoom != null) {
                    await prov.refreshExecutionPulse();
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh Status'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final digest =
                      'OpsHub Status - ${DateTime.now().toIso8601String()}\n'
                      'Pulse: ${prov.executionPulse?.status}\n'
                      'Score: ${prov.executionPulse?.score}/100';
                  await Clipboard.setData(ClipboardData(text: digest));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Status copie')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Copy Status'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentExportsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prov = context.watch<RoomProvider>();

    final exports = prov.shareHistory.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Exports',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (exports.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Aucun export recent',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ...exports.map(
              (exp) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      exp.target == 'slack'
                          ? Icons.work_outlined
                          : Icons.description_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exp.target.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatExportDate(exp.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (exp.isSuccess)
                      const Icon(Icons.check_circle_outlined,
                          size: 16, color: Color(0xFF2E8B57))
                    else
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Retry'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 24),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatExportDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  } else if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  } else {
    return '${diff.inDays}d ago';
  }
}

String _executionPulseLabel(String status) {
  switch (status) {
    case 'critical':
      return 'Critique';
    case 'attention':
      return 'Attention';
    case 'on_track':
    default:
      return 'Sous controle';
  }
}

Color _executionPulseColor(String status, ColorScheme scheme) {
  switch (status) {
    case 'critical':
      return scheme.error;
    case 'attention':
      return scheme.tertiary;
    case 'on_track':
    default:
      return const Color(0xFF2E8B57);
  }
}
