import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AccessibleVideoCard extends StatelessWidget {
  final VideoModel video;
  final VoidCallback onTap;
  final bool isFavorite;
  final Function(bool) onFavoriteToggle;

  const AccessibleVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.isFavorite = false,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vidéo : ${video.title}',
      value: video.description,
      button: true,
      enabled: true,
      child: MergeSemantics(
        child: Card(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Semantics(
                          image: true,
                          label: 'Miniature de la vidéo',
                          child: OptimizedImage(
                            imageUrl: video.thumbnailUrl,
                            width: double.infinity,
                            height: 200,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: AccessibleIconButton(
                          icon: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: isFavorite ? Colors.red : Colors.white,
                          ),
                          label: isFavorite
                              ? 'Retirer des favoris'
                              : 'Ajouter aux favoris',
                          onPressed: () => onFavoriteToggle(!isFavorite),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ExcludeSemantics(
                    child: Text(
                      video.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExcludeSemantics(
                    child: Text(
                      video.channelTitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
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

class AccessibleIconButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onPressed;

  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: label,
      child: IconButton(
        icon: icon,
        onPressed: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        tooltip: label,
      ),
    );
  }
}

class AccessibleSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;

  const AccessibleSearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      onTapHint: 'Rechercher des vidéos',
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          hintText: 'Rechercher des vidéos...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        style: const TextStyle(fontSize: 16),
        maxLines: 1,
      ),
    );
  }
}