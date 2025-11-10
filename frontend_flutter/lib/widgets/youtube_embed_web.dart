// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

final Set<String> _registeredViews = <String>{};

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
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final element = html.IFrameElement()
        ..src = embedUrl
        ..style.border = '0'
        ..width = '100%'
        ..height = '100%'
        ..allow =
            'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
        ..allowFullscreen = true;
      return element;
    });
    _registeredViews.add(viewType);
  }
  return AspectRatio(
    aspectRatio: 16 / 9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: HtmlElementView(viewType: viewType),
    ),
  );
}
