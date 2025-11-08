import 'package:flutter/material.dart';
import '../utils/adaptive_styles.dart';

/// VideoCard est un composant responsive qui affiche les informations d'une vidéo
/// Il s'adapte automatiquement à la taille de l'écran et au mode d'affichage
class VideoCard extends StatelessWidget {
  final VideoResult video;
  final Size? size;

  /// Crée une carte vidéo responsive
  /// 
  /// [video] : Les données de la vidéo à afficher
  /// [size] : Taille optionnelle pour surcharger la taille par défaut
  const VideoCard({
    super.key,
    required this.video,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cardSize = size ?? AdaptiveStyles.getVideoCardSize(context);
    final titleSize = AdaptiveStyles.getAdaptiveFontSize(context, 14);
    final subtitleSize = AdaptiveStyles.getAdaptiveFontSize(context, 12);

    return Container(
      width: cardSize.width,
      height: cardSize.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Image.network(
              video.thumbnailUrl,
              width: cardSize.width,
              height: cardSize.height * 0.6,
              fit: BoxFit.cover,
            ),
          ),
          
          // Informations
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  video.channelTitle,
                  style: TextStyle(
                    fontSize: subtitleSize,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}