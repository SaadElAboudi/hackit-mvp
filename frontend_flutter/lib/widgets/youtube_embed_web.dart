// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';

final Set<String> _registeredViews = <String>{};
html.IFrameElement? _lastIframeElement;
String? _lastBaseEmbedUrl;
String? _playerTargetOrigin; // e.g., https://www.youtube.com
bool _playerReady = false;
int? _pendingSeekSeconds;
StreamSubscription<html.MessageEvent>? _msgSub;

String _toEmbedUrl(String url) {
  try {
    final uri = Uri.parse(url);
    String? id;
    if (uri.host.contains('youtu.be')) {
      id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (uri.queryParameters.containsKey('v')) {
      id = uri.queryParameters['v'];
    } else {
      final idx = uri.pathSegments.indexOf('embed');
      if (idx != -1 && idx + 1 < uri.pathSegments.length) {
        id = uri.pathSegments[idx + 1];
      }
    }
    if (id == null || id.isEmpty) return url;
    // modestbranding, rel=0 to avoid unrelated videos, playsinline for iOS web
    // enablejsapi=1 to allow postMessage control; origin is set for YT API security.
    final origin = html.window.location.origin;
    return 'https://www.youtube.com/embed/$id?modestbranding=1&rel=0&playsinline=1&enablejsapi=1&origin=${Uri.encodeComponent(origin)}';
  } catch (_) {
    return url;
  }
}

Widget buildYouTubeEmbed(String url) {
  final embedUrl = _toEmbedUrl(url);
  final viewType = 'yt-iframe-${embedUrl.hashCode}';
  if (!_registeredViews.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final element = html.IFrameElement()
        ..src = embedUrl
        ..style.border = '0'
        ..width = '100%'
        ..height = '100%'
        ..allow =
            'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
        ..allowFullscreen = true;
      // Keep global reference for simple seek operations.
      _lastIframeElement = element;
      _lastBaseEmbedUrl = embedUrl; // without start param
      final srcUri = Uri.tryParse(embedUrl);
      _playerTargetOrigin = srcUri?.scheme != null && srcUri?.host != null
          ? '${srcUri!.scheme}://${srcUri.host}'
          : 'https://www.youtube.com';
      _ensurePlayerMessageChannel();
      _announceListening();
      return element;
    });
    _registeredViews.add(viewType);
  }
  // If already registered, attempt to recover existing element via querySelector.
  if (_lastIframeElement == null) {
    // Attempt naive lookup (not critical if fails).
    final elements = html.document.getElementsByTagName('iframe');
    if (elements.isNotEmpty) {
      _lastIframeElement = elements.last as html.IFrameElement?;
      _lastBaseEmbedUrl ??= embedUrl;
      final srcUri = Uri.tryParse(_lastIframeElement!.src);
      _playerTargetOrigin = srcUri?.scheme != null && srcUri?.host != null
          ? '${srcUri!.scheme}://${srcUri.host}'
          : 'https://www.youtube.com';
      _ensurePlayerMessageChannel();
      _announceListening();
    }
  }
  return AspectRatio(
    aspectRatio: 16 / 9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: HtmlElementView(viewType: viewType),
    ),
  );
}

/// Seek inside the last embedded YouTube iframe by updating start param.
/// This uses a simple src URL mutation; it restarts playback at the timestamp.
void seekYouTube(int seconds) {
  if (seconds < 0) return;
  final iframe = _lastIframeElement;
  final base = _lastBaseEmbedUrl;
  if (iframe == null || base == null) return;
  try {
    if (!_playerReady) {
      _pendingSeekSeconds = seconds;
      _announceListening();
    }
    // Preferred: Send postMessage commands to the Player (no reload).
    _postToPlayer({
      'event': 'command',
      'func': 'seekTo',
      'args': [seconds, true],
    });
    _postToPlayer({
      'event': 'command',
      'func': 'playVideo',
      'args': [],
    });

    // Fallback: mutate src if postMessage channel not ready (e.g., no contentWindow).
    Future.delayed(const Duration(milliseconds: 250), () {
      if (iframe.contentWindow == null) {
        final uri = Uri.parse(base);
        final params = Map<String, String>.from(uri.queryParameters);
        params['start'] = seconds.toString();
        params['autoplay'] = '1';
        final newUrl = uri.replace(queryParameters: params).toString();
        if (iframe.src != newUrl) {
          iframe.src = newUrl;
        }
      }
    });
  } catch (_) {
    // swallow: malformed base url should not crash app
  }
}

void _ensurePlayerMessageChannel() {
  _msgSub ??= html.window.onMessage.listen((event) {
    // YouTube sometimes sends stringified JSON; handle both.
    dynamic data = event.data;
    try {
      if (data is String) {
        data = data.trim();
        if (data.startsWith('{') && data.endsWith('}')) {
          data = html.window.jsonDecode(data);
        }
      }
    } catch (_) {
      // ignore malformed payloads
    }
    if (data is Map) {
      final e = data['event'];
      if (e == 'onReady') {
        _playerReady = true;
        final pending = _pendingSeekSeconds;
        _pendingSeekSeconds = null;
        if (pending != null) {
          // Immediately perform the pending seek
          _postToPlayer({
            'event': 'command',
            'func': 'seekTo',
            'args': [pending, true],
          });
          _postToPlayer({
            'event': 'command',
            'func': 'playVideo',
            'args': [],
          });
        }
      }
    }
  });
}

void _announceListening() {
  final iframe = _lastIframeElement;
  if (iframe?.contentWindow == null) return;
  _postToPlayer({
    'event': 'listening',
    'id': 'yt-player',
  });
}

void _postToPlayer(Object message) {
  final iframe = _lastIframeElement;
  final origin = _playerTargetOrigin ?? 'https://www.youtube.com';
  iframe?.contentWindow?.postMessage(message, origin);
}
