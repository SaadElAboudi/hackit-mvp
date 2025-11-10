// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

final Set<String> _registeredViews = <String>{};
html.IFrameElement? _lastIframeElement;
String? _lastBaseEmbedUrl;

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
    return 'https://www.youtube.com/embed/$id?modestbranding=1&rel=0&playsinline=1';
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
    final uri = Uri.parse(base);
    final params = Map<String, String>.from(uri.queryParameters);
    params['start'] = seconds.toString();
    params['autoplay'] = '1';
    final newUrl = uri.replace(queryParameters: params).toString();
    // Avoid unnecessary reload if already at target (best-effort by comparing src without start).
    if (iframe.src != newUrl) {
      iframe.src = newUrl;
    }
  } catch (_) {
    // swallow: malformed base url should not crash app
  }
}
