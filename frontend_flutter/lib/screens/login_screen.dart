import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/google_auth_provider.dart';
import '../widgets/app_scaffold.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Connexion',
      child: _LoginForm(),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginForm> {
  bool _loadingGoogle = false;
  String? _errorGoogle;
  String _email = '';
  String _password = '';
  String? _errorDemo;

  Future<void> _signInWithGoogle(BuildContext context) async {
    setState(() {
      _loadingGoogle = true;
      _errorGoogle = null;
    });
    final googleAuth = Provider.of<GoogleAuthProvider>(context, listen: false);
    try {
      await googleAuth.signIn();
      if (googleAuth.user != null) {
        Navigator.of(context).pushReplacementNamed('/');
      } else {
        setState(() {
          _errorGoogle = "Échec de la connexion Google.";
        });
      }
    } catch (e) {
      setState(() {
        _errorGoogle = "Erreur: $e";
      });
    } finally {
      setState(() {
        _loadingGoogle = false;
      });
    }
  }

  Future<void> _signInUser(BuildContext context) async {
    setState(() {
      _errorDemo = null;
    });
    if (_email.trim().isEmpty || _password.trim().isEmpty) {
      setState(() {
        _errorDemo = "Veuillez entrer un login et un mot de passe.";
      });
      return;
    }
    try {
      final uri = Uri.parse('http://localhost:3000/api/users/login');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: '{"email":"$_email","password":"$_password"}',
      );
      if (res.statusCode == 200) {
        // Parse token from backend response
        String? token;
        try {
          final data = res.body;
          if (data.isNotEmpty) {
            final json = data.contains('{') ? data : null;
            if (json != null) {
              final decoded = jsonDecode(json);
              token = decoded['token'] as String?;
            }
          }
        } catch (_) {}
        if (token != null && token.isNotEmpty) {
          // Save token in SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
        }
        Navigator.of(context).pushReplacementNamed('/');
      } else {
        setState(() {
          // Try to parse error message from backend
          String msg = "Identifiants invalides.";
          try {
            final err = res.body;
            if (err.isNotEmpty) msg = err;
          } catch (_) {}
          _errorDemo = msg;
        });
      }
    } catch (e) {
      setState(() {
        _errorDemo = "Erreur: $e";
      });
    }
  }

  void _showRegisterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        String email = '';
        String password = '';
        String? error;
        bool loading = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Créer un compte'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(labelText: 'Email'),
                    onChanged: (value) => email = value,
                  ),
                  SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(labelText: 'Mot de passe'),
                    obscureText: true,
                    onChanged: (value) => password = value,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: TextStyle(color: Colors.red)),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          setState(() => loading = true);
                          error = null;
                          try {
                            final response =
                                await _registerUser(email, password);
                            if (response['success'] == true) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Inscription réussie !')),
                              );
                            } else {
                              setState(() => error =
                                  response['error'] ?? 'Erreur inconnue');
                            }
                          } catch (e) {
                            setState(() => error = 'Erreur: $e');
                          } finally {
                            setState(() => loading = false);
                          }
                        },
                  child: loading
                      ? CircularProgressIndicator()
                      : Text('S’inscrire'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _registerUser(
      String email, String password) async {
    try {
      final uri = Uri.parse('http://localhost:3000/api/users/register');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: '{"email":"$email","password":"$password"}',
      );
      if (res.statusCode == 201) {
        return {'success': true};
      } else {
        final error = res.body;
        return {'success': false, 'error': error};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Color(0xFFF6F7FB),
        elevation: 0,
        centerTitle: true,
        title: const Text('Connexion',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 80, color: Colors.black),
              SizedBox(height: 24),
              Text('Connectez-vous',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
              SizedBox(height: 18),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  filled: true,
                  fillColor: Color(0xFFF6F7FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _email = value),
              ),
              SizedBox(height: 14),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  labelStyle: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  filled: true,
                  fillColor: Color(0xFFF6F7FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                obscureText: true,
                onChanged: (value) => setState(() => _password = value),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _signInUser(context),
                child: Text('Se connecter',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.blue.shade900,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  elevation: 2,
                ),
              ),
              SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => _showRegisterDialog(context),
                child: Text('Créer un compte',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  elevation: 2,
                ),
              ),
              SizedBox(height: 14),
              if (_errorDemo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_errorDemo!,
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              SizedBox(height: 18),
              if (_errorGoogle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_errorGoogle!,
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loadingGoogle
                          ? null
                          : () => _signInWithGoogle(context),
                      icon: _loadingGoogle
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Icon(Icons.login, color: Colors.white),
                      label: Text('Continuer avec Google',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding:
                            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        elevation: 2,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        // Générer un userId anonyme et le stocker
                        final prefs = await SharedPreferences.getInstance();
                        String anonId =
                            'anon_${DateTime.now().millisecondsSinceEpoch}${(1000 + (10000 * (new DateTime.now().microsecond % 1000))).toString()}';
                        await prefs.setString('user_id', anonId);
                        Navigator.of(context).pushReplacementNamed('/');
                      },
                      child: Text('Continuer en invité',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding:
                            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
