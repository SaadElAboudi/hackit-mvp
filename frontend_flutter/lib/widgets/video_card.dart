import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';

class VideoCard extends StatefulWidget {
  final String title;
  final String videoUrl;
  const VideoCard({super.key, required this.title, required this.videoUrl});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openUrl(BuildContext context) async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) {
      _showError(context, 'URL invalide');
      return;
    }

    final messenger = ScaffoldMessenger.of(context); // capture before async
    try {
      final success = await launchUrl(uri);
      if (!success) {
        if (!mounted) return; // widget may have unmounted during await
        messenger.showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir la vidéo')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Erreur lors de l\'ouverture de la vidéo')),
      );
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = _isPressed
        ? 0.97
        : _isHovered
            ? 1.02
            : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ScaleTransition(
        scale: _scaleAnimation.drive(Tween(begin: 1.0, end: scale)),
        child: Card(
          elevation: _isPressed
              ? 1
              : _isHovered
                  ? 4
                  : 2,
          child: InkWell(
            onTapDown: _handleTapDown,
            onTapUp: _handleTapUp,
            onTapCancel: _handleTapCancel,
            onTap: () => _openUrl(context),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(AdaptiveSpacing.medium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.play_circle_fill_rounded,
                          color: scheme.primary),
                      SizedBox(width: AdaptiveSpacing.small),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: SizeConfig.adaptiveFontSize(16),
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AdaptiveSpacing.small),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openUrl(context),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Ouvrir la vidéo'),
                      ),
                      SizedBox(width: AdaptiveSpacing.small),
                      Icon(Icons.launch,
                          size: SizeConfig.adaptiveSize(16),
                          color: scheme.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
