import 'package:flutter/material.dart';
import '../utils/responsive_layout.dart';

/// Un widget qui gère les transitions fluides lors des changements de taille d'écran
class AdaptiveLayoutTransition extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;

  /// Crée un widget de transition adaptative
  /// 
  /// [child] : Le widget à afficher
  /// [duration] : La durée de la transition (par défaut 300ms)
  /// [curve] : La courbe d'animation (par défaut easeInOut)
  const AdaptiveLayoutTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOut,
  });

  @override
  State<AdaptiveLayoutTransition> createState() => _AdaptiveLayoutTransitionState();
}

class _AdaptiveLayoutTransitionState extends State<AdaptiveLayoutTransition> {
  late Size _screenSize;
  late String _currentLayout;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateLayoutState();
  }

  void _updateLayoutState() {
    _screenSize = MediaQuery.of(context).size;
    if (ResponsiveLayout.isDesktop(context)) {
      _currentLayout = 'desktop';
    } else if (ResponsiveLayout.isTablet(context)) {
      _currentLayout = 'tablet';
    } else {
      _currentLayout = 'mobile';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: widget.duration,
      curve: widget.curve,
      width: _screenSize.width,
      height: _screenSize.height,
      child: widget.child,
    );
  }
}