import 'package:flutter/material.dart';
import '../services/project_service.dart';
import '../services/personal_ai_service.dart';

/// Profile & settings screen: update name, Gemini key, theme.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _keyObscured = true;
  bool _saving = false;
  bool _validatingKey = false;
  String? _keyError;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = ProjectService.currentDisplayName ?? '';
    _keyCtrl.text = ProjectService.geminiKey ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final key = _keyCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le prénom ne peut pas être vide')),
      );
      return;
    }

    // Validate key only if changed
    if (key != (ProjectService.geminiKey ?? '')) {
      if (key.isNotEmpty && !key.startsWith('AIza')) {
        setState(() => _keyError = 'Une clé Gemini commence par "AIza"');
        return;
      }
      if (key.isNotEmpty) {
        setState(() {
          _validatingKey = true;
          _keyError = null;
        });
        final error = await PersonalAiService.validateKey(key);
        if (!mounted) return;
        if (error != null) {
          setState(() {
            _validatingKey = false;
            _keyError = error;
          });
          return;
        }
        setState(() => _validatingKey = false);
      }
    }

    setState(() => _saving = true);
    await ProjectService.setDisplayName(name);
    await ProjectService.setGeminiKey(key);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _keyError = null;
      _successMsg = 'Profil mis à jour ✓';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _successMsg = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBusy = _saving || _validatingKey;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Profil & Paramètres'),
        backgroundColor: scheme.surface,
        elevation: 0,
        actions: [
          if (_successMsg != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(_successMsg!,
                    style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
                backgroundColor: scheme.primary,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    (ProjectService.currentDisplayName ?? '?')[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              _SectionTitle('Identité'),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Prénom / pseudo',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              _SectionTitle('Copilote IA personnel'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 18, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Votre clé reste sur cet appareil uniquement — jamais transmise à nos serveurs.',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyCtrl,
                obscureText: _keyObscured,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Clé API Gemini',
                  hintText: 'AIzaSy…',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: const OutlineInputBorder(),
                  errorText: _keyError,
                  helperText:
                      'Obtenez une clé gratuite sur aistudio.google.com',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _keyObscured ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setState(() => _keyObscured = !_keyObscured),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: isBusy ? null : _save,
                  icon: isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_validatingKey
                      ? 'Validation de la clé…'
                      : _saving
                          ? 'Enregistrement…'
                          : 'Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.primary,
        letterSpacing: 0.8,
      ),
    );
  }
}
