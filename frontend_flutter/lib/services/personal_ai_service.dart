import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api/api_service.dart';

/// Represents a single turn in the AI conversation.
class AiMessage {
  final String role; // 'user' | 'model'
  final String text;
  const AiMessage({required this.role, required this.text});
}

/// Calls the backend `/api/ai/chat` endpoint which proxies to Gemini using the
/// server-side API key. No key is ever stored or sent by the client.
class PersonalAiService {
  static String get _backendUrl => '${ApiService.staticBaseUrl}/api/ai/chat';

  /// Send [history] (prior turns) + [userMessage] and return the model's reply.
  /// Throws a human-readable [Exception] on failure.
  Future<String> chat(
    List<AiMessage> history,
    String userMessage, {
    String? systemPrompt,
  }) async {
    final body = <String, dynamic>{
      'message': userMessage,
      'history': history.map((m) => {'role': m.role, 'text': m.text}).toList(),
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
    };

    final response = await http
        .post(
          Uri.parse(_backendUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode == 429) {
      throw Exception('Quota IA dépassé. Réessaie dans quelques secondes.');
    }
    if (response.statusCode != 200) {
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(json['error'] ?? 'Erreur IA (${response.statusCode}).');
      } catch (_) {
        throw Exception('Erreur IA (${response.statusCode}).');
      }
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['reply']?.toString() ?? '';
  }
}
