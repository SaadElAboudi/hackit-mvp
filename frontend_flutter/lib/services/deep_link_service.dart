import 'package:injectable/injectable.dart';
import 'package:uni_links/uni_links.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:async';

@singleton
class DeepLinkService {
  static const String _scheme = 'hackitmvp';
  final _deepLinkController = StreamController<Uri>.broadcast();

  Stream<Uri> get deepLinks => _deepLinkController.stream;

  Future<void> init() async {
    // Gérer les liens initiaux
    try {
      final initialLink = await getInitialUri();
      if (initialLink != null) {
        _handleDeepLink(initialLink);
      }
    } on PlatformException {
      // Gérer l'erreur de lien initial
      print('Error retrieving initial deep link');
    }

    // Écouter les liens entrants
    uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    }, onError: (err) {
      print('Error handling deep link: $err');
    });
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == _scheme) {
      _deepLinkController.add(uri);
    }
  }

  // Génération des liens deep link
  String generateVideoLink(String videoId) {
    return '$_scheme://video/$videoId';
  }

  String generateSearchLink(String query) {
    final encodedQuery = Uri.encodeComponent(query);
    return '$_scheme://search?q=$encodedQuery';
  }

  String generatePlaylistLink(String playlistId) {
    return '$_scheme://playlist/$playlistId';
  }

  // Partage de contenu
  Future<void> shareVideo({
    required String videoId,
    required String title,
    String? description,
  }) async {
    final link = generateVideoLink(videoId);
    final message = 'Regardez "$title" sur Hackit MVP\n$link';
    await Share.share(message);
  }

  Future<void> sharePlaylist({
    required String playlistId,
    required String title,
  }) async {
    final link = generatePlaylistLink(playlistId);
    final message = 'Découvrez la playlist "$title" sur Hackit MVP\n$link';
    await Share.share(message);
  }

  // Parsing des deep links
  DeepLinkData? parseDeepLink(Uri uri) {
    if (uri.scheme != _scheme) return null;

    switch (uri.path) {
      case '/video':
        final videoId = uri.pathSegments.last;
        return VideoDeepLink(videoId);

      case '/search':
        final query = uri.queryParameters['q'];
        if (query != null) {
          return SearchDeepLink(Uri.decodeComponent(query));
        }
        return null;

      case '/playlist':
        final playlistId = uri.pathSegments.last;
        return PlaylistDeepLink(playlistId);

      default:
        return null;
    }
  }

  void dispose() {
    _deepLinkController.close();
  }
}

// Classes pour représenter les différents types de deep links
abstract class DeepLinkData {}

class VideoDeepLink extends DeepLinkData {
  final String videoId;
  VideoDeepLink(this.videoId);
}

class SearchDeepLink extends DeepLinkData {
  final String query;
  SearchDeepLink(this.query);
}

class PlaylistDeepLink extends DeepLinkData {
  final String playlistId;
  PlaylistDeepLink(this.playlistId);
}