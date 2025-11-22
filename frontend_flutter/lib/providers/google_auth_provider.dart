import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../models/demo_user.dart';

class GoogleAuthProvider with ChangeNotifier {
  DemoUser? demoUser;
  GoogleSignInAccount? _user;

  // Retourne l'utilisateur courant (Google ou démo)
  dynamic get user => demoUser ?? _user;
  bool get isDemo => demoUser != null;

  // TODO: Replace with your actual Google web client ID
  static const String _webClientId =
      '895881564037-24opo799rloeji1i4rkri476i4m0oorn.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: _webClientId,
    scopes: ['email', 'profile'],
  );

  Future<void> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        _user = account;
        notifyListeners();
      }
    } catch (e) {
      print('Google sign-in error: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _user = null;
    notifyListeners();
  }

  Future<void> signInDemo() async {
    demoUser = DemoUser(
      id: 'demo_user',
      name: 'Démo',
      email: 'demo@hackit.app',
      avatarUrl: null,
      isDemo: true,
    );
    notifyListeners();
  }

  // Utilitaire pour appeler le backend avec la session Google
  Future<http.Response> callBackend(String endpoint,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final headers = <String, String>{};
    if (isDemo && demoUser != null) {
      headers['x-user-id'] = demoUser!.id;
      // Optionally set a dummy token for demo users
      headers['Authorization'] = 'Bearer DEMO_TOKEN';
    } else if (_user != null) {
      headers['x-user-id'] = _user!.id;
      final auth = await _user!.authentication;
      // Toujours envoyer le token Google si présent
      if (auth.idToken != null) {
        headers['Authorization'] = 'Bearer ${auth.idToken}';
      } else if (auth.accessToken != null) {
        headers['Authorization'] = 'Bearer ${auth.accessToken}';
      }
    }
    final uri = Uri.parse(endpoint);
    // Pour la gestion des cookies/session Passport, il faut utiliser http.Client et activer cookie persistence
    final client = http.Client();
    http.Response response;
    if (method == 'POST') {
      response = await client.post(uri, headers: headers, body: body);
    } else if (method == 'PATCH') {
      response = await client.patch(uri, headers: headers, body: body);
    } else {
      response = await client.get(uri, headers: headers);
    }
    client.close();
    return response;
  }
}
