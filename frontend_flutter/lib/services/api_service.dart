import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../models/base_search_result.dart';

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
  static const String baseUrl = 'http://localhost:3000';
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
