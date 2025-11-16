import '../core/responsive/size_config.dart';
import '../widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/google_auth_provider.dart';
import 'root_tabs.dart';

class LoginScreen extends StatelessWidget {
  final VoidCallback? onGuest;
  const LoginScreen({super.key, this.onGuest});

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final googleAuth = Provider.of<GoogleAuthProvider>(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
          child: googleAuth.user == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    EmptyState(
                      icon: Icons.login,
                      title: 'Bienvenue sur Hackit',
                      subtitle:
                          'Connectez-vous avec Google ou continuez en mode invité.',
                      actionLabel: 'Demander de l\'aide',
                      onAction: () {
                        Navigator.of(context).pushNamed('/support');
                      },
                    ),
                    SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: Icon(Icons.login),
                      label: Text('Connexion avec Google'),
                      onPressed: () => googleAuth.signIn(),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(180, 44),
                        textStyle: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                        padding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: Icon(Icons.person_outline),
                      label: Text('Continuer en invité'),
                      onPressed: onGuest,
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(180, 44),
                        textStyle: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                        padding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: googleAuth.user!.photoUrl != null
                          ? NetworkImage(googleAuth.user!.photoUrl!)
                          : null,
                      child: googleAuth.user!.photoUrl == null
                          ? const Icon(Icons.person, size: 32)
                          : null,
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Connecté en tant que',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    SizedBox(height: 6),
                    Text(
                      googleAuth.user!.displayName ?? '',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(180, 44),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Déconnexion'),
                      onPressed: () => googleAuth.signOut(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
