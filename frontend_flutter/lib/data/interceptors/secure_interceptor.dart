import 'package:dio/dio.dart';
import '../services/security_service.dart';

class SecureInterceptor extends Interceptor {
  final SecurityService _securityService;

  SecureInterceptor(this._securityService);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Ajouter les en-têtes de sécurité
    options.headers['X-Content-Type-Options'] = 'nosniff';
    options.headers['X-Frame-Options'] = 'DENY';
    options.headers['X-XSS-Protection'] = '1; mode=block';
    options.headers['Content-Security-Policy'] = "default-src 'self'";

    // Ajouter le token d'authentification s'il existe
    if (options.extra['requiresAuth'] == true) {
      final token = await _securityService.getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    // Sanitiser les paramètres de requête
    if (options.queryParameters.isNotEmpty) {
      final sanitizedParams = Map<String, dynamic>.from(options.queryParameters);
      sanitizedParams.forEach((key, value) {
        if (value is String) {
          sanitizedParams[key] = _securityService.sanitizeInput(value);
        }
      });
      options.queryParameters = sanitizedParams;
    }

    // Sanitiser le corps de la requête
    if (options.data != null && options.data is Map) {
      final sanitizedData = Map<String, dynamic>.from(options.data);
      sanitizedData.forEach((key, value) {
        if (value is String) {
          sanitizedData[key] = _securityService.sanitizeInput(value);
        }
      });
      options.data = sanitizedData;
    }

    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Vérifier les en-têtes de sécurité dans la réponse
    final headers = response.headers;
    if (!headers.map.containsKey('X-Content-Type-Options') ||
        !headers.map.containsKey('X-Frame-Options')) {
      print('Warning: Missing security headers in response');
    }

    // Vérifier si la réponse contient un nouveau token
    final newToken = headers.value('X-Auth-Token');
    if (newToken != null) {
      _securityService.saveToken(newToken);
    }

    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Gérer les erreurs de sécurité
    if (err.response?.statusCode == 401) {
      // Token expiré ou invalide
      _securityService.deleteToken();
      // Rediriger vers la page de connexion
    } else if (err.response?.statusCode == 403) {
      // Accès refusé
      print('Security warning: Access denied');
    }

    super.onError(err, handler);
  }
}