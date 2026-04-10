import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents a single turn in the AI conversation.
class AiMessage {
  final String role; // 'user' | 'model'
  final String text;
  const AiMessage({required this.role, required this.text});

  Map<String, dynamic> toGeminiPart() => {
        'role': role,
        'parts': [
          {'text': text}
        ],
      };
}

/// Calls the Gemini API directly from the Flutter client using the user's own
/// personal API key. Nothing passes through the app backend.
///
/// Model: gemini-2.0-flash (stable, generous free tier — 15 req/min, 1500 req/day).
class PersonalAiService {
  static const _model = 'gemini-2.0-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  final String apiKey;
  PersonalAiService({required this.apiKey});

  /// Send [history] (list of prior turns) + [userMessage] and return the
  /// model's text reply. Throws a human-readable [Exception] on failure.
  Future<String> chat(
    List<AiMessage> history,
    String userMessage, {
    String? systemPrompt,
  }) async {
    final contents = [
      ...history.map((m) => m.toGeminiPart()),
      {
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ],
      },
    ];

    final body = <String, dynamic>{
      'contents': contents,
      if (systemPrompt != null)
        'system_instruction': {
          'parts': [
            {'text': systemPrompt}
          ]
        },
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1024,
      },
    };

    final response = await http
        .post(
          Uri.parse('$_baseUrl?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401 || response.statusCode == 403) {
      final msg = _extractApiError(response.body);
      throw Exception(msg ?? 'Clé API invalide. Vérifie tes paramètres de profil.');
    }
    if (response.statusCode == 429) {
      throw Exception(
          'Quota Gemini dépassé. Attends quelques secondes et réessaie.');
    }
    if (response.statusCode != 200) {
      final msg = _extractApiError(response.body);
      throw Exception(msg ?? 'Erreur Gemini (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Réponse vide de Gemini.');
    }
    final parts = (candidates[0]['content']['parts'] as List?) ?? [];
    if (parts.isEmpty) {
      throw Exception('Réponse vide de Gemini.');
    }
    return parts[0]['text']?.toString() ?? '';
  }

  /// Validates the key with a minimal request. Returns null on success,
  /// or an error message string.
  ///
  /// A 429 (rate-limit) is treated as success: Google authenticated the key,
  /// it is valid — the user just needs to wait before making more requests.
  static Future<String?> validateKey(String key) async {
    try {
      final trimmed = key.trim();
      // Basic format check before hitting the network
      if (!trimmed.startsWith('AIza') || trimmed.length < 20) {
        return 'La clé doit commencer par "AIza" et faire au moins 20 caractères.';
      }

      final svc = PersonalAiService(apiKey: trimmed);
      await svc.chat([], 'ok', systemPrompt: 'Reply with one word.');
      return null; // success
    } on Exception catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      // 429 = key is valid, Google just rate-limited us
      if (msg.contains('Quota') || msg.contains('429')) return null;
      return msg;
    } catch (_) {
      return 'Erreur inattendue lors de la validation.';
    }
  }

  /// Tries to extract a human-readable message from a Gemini error response.
  static String? _extractApiError(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map?;
      return error?['message'] as String?;
    } catch (_) {
      return null;
    }
  }
}
