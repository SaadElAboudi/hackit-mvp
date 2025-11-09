import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform; // guarded below for non-web only
import 'package:injectable/injectable.dart';
import '../models/base_search_result.dart';
import '../models/stream_event.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => statusCode != null
      ? 'ApiException: $message (Status: $statusCode)'
      : 'ApiException: $message';
}

@singleton
class ApiService {
  // Resolve base URL with priority: dart-define > environment fallback > default.
  // Use --dart-define=API_BASE_URL=https://prod.example.com when building.
  static final String baseUrl = (() {
    // 1) Prefer compile-time define
    final fromDefine =
        const String.fromEnvironment('API_BASE_URL', defaultValue: '').trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    // 2) On web, avoid Platform.environment (unsupported) and default to localhost:3000
    if (kIsWeb) return 'http://localhost:3000';
    // 3) On native, try env var, fallback to localhost
    try {
      return Platform.environment['API_BASE_URL'] ?? 'http://localhost:3000';
    } catch (_) {
      return 'http://localhost:3000';
    }
  })();

  static const int maxRetries = 3;
  static const int timeoutSeconds = 10;
  final http.Client _client;

  ApiService(this._client);

  factory ApiService.create() {
    return ApiService(http.Client());
  }

  Future<BaseSearchResult> searchVideos(String query) async {
    int attempts = 0;
    late dynamic lastError;

    while (attempts < maxRetries) {
      try {
        final uri = Uri.parse('$baseUrl/api/search');
        final response = await _client
            .post(uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'query': query}))
            .timeout(const Duration(seconds: timeoutSeconds));

        final body = _parseResponse(response);
        if (response.statusCode == 200) {
          return BaseSearchResult(
            title: body['title'] ?? '',
            steps: List<String>.from(body['steps'] ?? []),
            videoUrl: body['videoUrl'] ?? '',
            source: body['source'] ?? '',
            summary: body['summary'],
            citations: (body['citations'] as List<dynamic>? ?? [])
                .map((e) => Citation.fromMap(e as Map<String, dynamic>))
                .toList(),
            chapters: (body['chapters'] as List<dynamic>? ?? [])
                .map((e) => Chapter.fromMap(e as Map<String, dynamic>))
                .toList(),
            metadata: {
              'timestamp': DateTime.now().toIso8601String(),
              'query': query,
            },
          );
        }

        // Handle specific status codes with user-friendly French messages
        switch (response.statusCode) {
          case 400:
            throw ApiException('Requête invalide', statusCode: 400);
          case 401:
            throw ApiException('Non autorisé', statusCode: 401);
          case 404:
            // Distinguish between "no video found" vs generic not found
            final detail =
                body['detail'] ?? body['error'] ?? 'Contenu introuvable';
            // Backend sends error: "Not found" with detail explanatory text
            throw ApiException(
                detail == 'Not found'
                    ? 'Aucune vidéo trouvée'
                    : detail.toString(),
                statusCode: 404);
          case 429:
            // Rate limit - wait longer before retry
            await Future.delayed(Duration(seconds: attempts + 1));
            attempts++;
            continue;
          default:
            throw ApiException(
                'Erreur serveur: ${body['error'] ?? 'Unknown error'}',
                statusCode: response.statusCode);
        }
      } on TimeoutException {
        lastError = ApiException('Request timeout');
        if (++attempts < maxRetries) {
          await Future.delayed(Duration(seconds: attempts));
          continue;
        }
      } on FormatException catch (e) {
        throw ApiException('Format error: ${e.message}');
      } catch (e) {
        lastError = e is ApiException ? e : ApiException(e.toString());
        if (++attempts < maxRetries) {
          await Future.delayed(Duration(seconds: attempts));
          continue;
        }
      }
    }

    throw lastError ?? ApiException('Unknown error after $maxRetries attempts');
  }

  // Stream search via SSE endpoint. Emits meta/partial/done events.
  Stream<StreamEvent> searchVideosStream(String query) async* {
    final uri = Uri.parse(
        '$baseUrl/api/search/stream?query=${Uri.encodeQueryComponent(query)}');
    final request = http.Request('GET', uri);
    final streamed = await _client.send(request);
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw ApiException('Stream error: HTTP ${streamed.statusCode} $body',
          statusCode: streamed.statusCode);
    }

    // SSE is a text stream with lines; we read as utf8 and parse data: lines.
    // We'll collect lines until a blank line, then parse the JSON after 'data: '.
    final decoder = utf8.decoder.bind(streamed.stream);
    final buffer = StringBuffer();
    await for (final chunk in decoder) {
      buffer.write(chunk);
      var text = buffer.toString();
      int idx;
      // Process complete events separated by double newlines.
      while ((idx = text.indexOf('\n\n')) != -1) {
        final eventBlock = text.substring(0, idx);
        text = text.substring(idx + 2);
        // Extract data lines
        final lines = eventBlock.split('\n');
        final dataLine = lines.firstWhere(
          (l) => l.startsWith('data:'),
          orElse: () => '',
        );
        if (dataLine.isNotEmpty) {
          final jsonStr = dataLine.substring(5).trim();
          try {
            final map = json.decode(jsonStr) as Map<String, dynamic>;
            yield StreamEvent.fromJson(map);
          } catch (_) {
            // ignore malformed chunks
          }
        }
      }
      // Keep leftover in buffer
      buffer
        ..clear()
        ..write(text);
    }
  }

  // Simple health ping to detect backend availability and meta info.
  Future<Map<String, dynamic>> pingHealth(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final uri = Uri.parse('$baseUrl/health');
    try {
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode == 200) {
        final map = json.decode(resp.body) as Map<String, dynamic>;
        return map;
      }
      return {'ok': false, 'status': resp.statusCode};
    } on TimeoutException {
      return {'ok': false, 'timeout': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // Removed getVideoDetails to simplify API surface; not used by the app.

  Map<String, dynamic> _parseResponse(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException('Réponse invalide du serveur',
          statusCode: response.statusCode);
    }
  }
}
