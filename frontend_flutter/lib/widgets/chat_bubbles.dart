import 'dart:async';
import 'package:flutter/material.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';

class UserBubble extends StatefulWidget {
  final String text;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final bool disabled;
  final Color textColor;
  const UserBubble({
    super.key,
    required this.text,
    this.onEdit,
    this.onRegenerate,
    this.disabled = false,
    this.textColor = Colors.white,
  });

  @override
  State<UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<UserBubble> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final showActions = isMobile || _hovered;

    final bubble = Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        widget.text,
        style: TextStyle(
          fontSize: SizeConfig.adaptiveFontSize(15),
          height: 1.35,
          fontWeight: FontWeight.w500,
          color: scheme.onPrimary,
        ),
      ),
    );

    final hasActions = widget.onEdit != null || widget.onRegenerate != null;
    final actions = hasActions
        ? AnimatedOpacity(
            opacity: showActions ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: Padding(
              padding: EdgeInsets.only(top: AdaptiveSpacing.tiny),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onRegenerate != null)
                    Tooltip(
                      message: 'Relancer',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed:
                            widget.disabled ? null : widget.onRegenerate,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                  if (widget.onEdit != null)
                    Tooltip(
                      message: 'Modifier',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: widget.disabled ? null : widget.onEdit,
                        icon: const Icon(Icons.edit_rounded),
                      ),
                    ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: SizeConfig.screenWidth * 0.85,
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              bubble,
              actions,
            ],
          ),
        ),
      ),
    );
  }
}

class AssistantContainer extends StatelessWidget {
  final Widget child;
  const AssistantContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(5),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: DefaultTextStyle(
          style: TextStyle(color: scheme.onSurface),
          child: child,
        ),
      ),
    );
  }
}

class LoadingBubbles extends StatefulWidget {
  const LoadingBubbles({super.key});

  @override
  State<LoadingBubbles> createState() => _LoadingBubblesState();
}

class _LoadingBubblesState extends State<LoadingBubbles>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    'Analyse du brief\u2026',
    'Structure du plan\u2026',
    'D\u00e9pendances & timeline\u2026',
    'Finalisation du livrable\u2026',
  ];

  int _stepIndex = 0;
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (mounted) {
        setState(() => _stepIndex = (_stepIndex + 1) % _steps.length);
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;

    Widget skeleton({double height = 15, double widthFactor = 1}) =>
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Container(
            width: SizeConfig.screenWidth * 0.6 * widthFactor,
            height: height,
            margin: EdgeInsets.only(bottom: AdaptiveSpacing.tiny + 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest
                  .withValues(alpha: 0.45 * _pulseAnim.value),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Row(
            key: ValueKey(_stepIndex),
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: _pulseAnim.value),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _steps[_stepIndex],
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: AdaptiveSpacing.small),
        Container(
          padding: EdgeInsets.all(AdaptiveSpacing.small + 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomLeft: const Radius.circular(4),
            ),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              skeleton(widthFactor: 0.4),
              skeleton(),
              skeleton(widthFactor: 0.85),
              skeleton(widthFactor: 0.75),
              skeleton(widthFactor: 0.55),
            ],
          ),
        ),
      ],
    );
  }
}
