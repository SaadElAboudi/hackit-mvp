import 'package:injectable/injectable.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/deep_link_service.dart';

@singleton
class ShareService {
  final DeepLinkService _deepLinkService;

  ShareService(this._deepLinkService);

  Future<void> shareVideo({
    required String videoId,
    required String title,
    required String thumbnailUrl,
    String? description,
  }) async {
    final link = _deepLinkService.generateVideoLink(videoId);
    final message = description != null
        ? '$title\n\n$description\n\n$link'
        : '$title\n\n$link';

    try {
      // Télécharger la miniature
      final thumbnail = await _downloadThumbnail(thumbnailUrl);
      if (thumbnail != null) {
        // Partager avec la miniature
        await Share.shareXFiles(
          [XFile(thumbnail.path)],
          text: message,
          subject: title,
        );
      } else {
        // Partager sans miniature
        await Share.share(message, subject: title);
      }
    } catch (e) {
      // En cas d'erreur, partager sans miniature
      await Share.share(message, subject: title);
    }
  }

  Future<void> sharePlaylist({
    required String playlistId,
    required String title,
    required List<String> videoTitles,
  }) async {
    final link = _deepLinkService.generatePlaylistLink(playlistId);
    var message = 'Playlist: $title\n\n';

    // Ajouter les titres des vidéos (limités à 5)
    final displayedVideos = videoTitles.take(5);
    message += displayedVideos.map((title) => '• $title').join('\n');

    if (videoTitles.length > 5) {
      message += '\n\n... et ${videoTitles.length - 5} autres vidéos';
    }

    message += '\n\n$link';

    await Share.share(message, subject: title);
  }

  Future<void> shareSearchResults({
    required String query,
    required int resultCount,
  }) async {
    final link = _deepLinkService.generateSearchLink(query);
    final message =
        'Découvrez $resultCount résultats pour "$query" sur Hackit MVP\n\n$link';

    await Share.share(message, subject: 'Résultats de recherche pour "$query"');
  }

  Future<File?> _downloadThumbnail(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/thumbnail.jpg');
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      debugPrint('Error downloading thumbnail: $e');
    }
    return null;
  }

  // Note: custom share image generation has been removed for now as it was unused.
}
