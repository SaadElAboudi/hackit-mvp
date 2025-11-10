import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../services/video_seek_service.dart';
import '../core/responsive/size_config.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../providers/history_favorites_provider.dart';

class VideoCard extends StatefulWidget {
  final String title;
  final String videoUrl;
  const VideoCard({super.key, required this.title, required this.videoUrl});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController
      _controller; // controller retained for potential future effects
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 150), vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openUrl(BuildContext context, {int? startSeconds}) async {
    final uri = Uri.tryParse(widget.videoUrl);
    final isValid = uri != null && uri.hasScheme && (uri.host.isNotEmpty);
    if (!isValid) {
      _showError(context, 'URL invalide');
      return;
    }

    final messenger = ScaffoldMessenger.of(context); // capture before async
    try {
      Uri toLaunch = uri;
      if (startSeconds != null && startSeconds >= 0) {
        final params = Map<String, String>.from(toLaunch.queryParameters);
        params['t'] = startSeconds.toString();
        toLaunch = toLaunch.replace(queryParameters: params);
      }
      final success = await launchUrl(toLaunch);
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
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    final scale = _isPressed
        ? 0.97
        : _isHovered
            ? 1.02
            : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        scale: scale,
        child: Card(
          elevation: _isPressed
              ? 1
              : _isHovered
                  ? 6
                  : 3,
          shadowColor: scheme.primary.withValues(alpha: 0.25),
          surfaceTintColor: scheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: GestureDetector(
            onTapDown: _handleTapDown,
            onTapUp: _handleTapUp,
            onTapCancel: _handleTapCancel,
            onTap: () => _openUrl(context),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _isHovered ? 0.08 : 0.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.primary.withValues(alpha: 0.15),
                            scheme.primaryContainer.withValues(alpha: 0.12),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(AdaptiveSpacing.medium + 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  scheme.primary.withValues(alpha: 0.85),
                                  scheme.primaryContainer
                                      .withValues(alpha: 0.9),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.play_circle_fill_rounded,
                                color: scheme.onPrimary, size: 28),
                          ),
                          SizedBox(width: AdaptiveSpacing.medium),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AdaptiveSpacing.small),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _openUrl(context),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Voir la vidéo →'),
                          ),
                          SizedBox(width: AdaptiveSpacing.small),
                          if (!VideoSeekService.instance.isRegistered)
                            TextButton.icon(
                              onPressed: () =>
                                  VideoSeekService.instance.register(
                                (d) => _openUrl(context,
                                    startSeconds: d.inSeconds),
                                baseUrl: widget.videoUrl,
                              ),
                              icon: const Icon(Icons.linked_camera, size: 18),
                              label: const Text('Activer le seek'),
                            ),
                          SizedBox(width: AdaptiveSpacing.small),
                          Builder(builder: (context) {
                            // Make the favorites toggle optional: if no provider is found, hide the control.
                            HistoryFavoritesProvider? favs;
                            try {
                              favs = context.watch<HistoryFavoritesProvider>();
                            } catch (_) {
                              favs = null;
                            }
                            if (favs == null) return const SizedBox.shrink();
                            final isFav = favs.isFavorite(widget.videoUrl);
                            return IconButton(
                              key: const Key('video_favorite_toggle'),
                              tooltip: isFav
                                  ? 'Retirer des favoris'
                                  : 'Ajouter aux favoris',
                              icon: Icon(
                                isFav
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: isFav ? Colors.amber : scheme.primary,
                                size: 20,
                              ),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                if (isFav) {
                                  await favs!.toggleFavorite(
                                    videoId: widget.videoUrl,
                                    title: widget.title,
                                    videoUrl: widget.videoUrl,
                                  );
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Retiré des favoris'),
                                      duration: Duration(milliseconds: 1200),
                                    ),
                                  );
                                } else {
                                  await favs!.toggleFavorite(
                                    videoId: widget.videoUrl,
                                    title: widget.title,
                                    videoUrl: widget.videoUrl,
                                  );
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Ajouté aux favoris'),
                                      duration: Duration(milliseconds: 1200),
                                    ),
                                  );
                                }
                              },
                            );
                          }),
                          Icon(
                            Icons.launch,
                            size: 16,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
