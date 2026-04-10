import 'package:flutter/material.dart';
import '../services/project_service.dart';
import '../services/personal_ai_service.dart';

/// First-launch onboarding: collect display name + Gemini API key.
/// The key is stored only in SharedPreferences — never sent to the backend.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();

  bool _keyObscured = true;
  bool _validating = false;
  String? _keyError;
  int _step = 0; // 0 = name, 1 = key

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_formKey.currentState!.validate()) return;
    if (_step == 0) {
      setState(() => _step = 1);
      return;
    }
    // Step 1: validate key
    setState(() {
      _validating = true;
      _keyError = null;
    });
    final error = await PersonalAiService.validateKey(_keyCtrl.text.trim());
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _validating = false;
        _keyError = error;
      });
      return;
    }
    await ProjectService.setDisplayName(_nameCtrl.text.trim());
    await ProjectService.setGeminiKey(_keyCtrl.text.trim());
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo / titre
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Hackit',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),

                    // Indicateur d'étape
                    Row(
                      children: [
                        _StepDot(active: _step == 0, done: _step > 0),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Divider(
                                color: _step > 0
                                    ? scheme.primary
                                    : scheme.outlineVariant)),
                        const SizedBox(width: 8),
                        _StepDot(active: _step == 1, done: false),
                      ],
                    ),
                    const SizedBox(height: 28),

                    if (_step == 0) ..._buildStepName(scheme),
                    if (_step == 1) ..._buildStepKey(scheme),

                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _validating ? null : _next,
                        child: _validating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(_step == 0
                                ? 'Continuer →'
                                : 'Accéder à mes salons'),
                      ),
                    ),

                    if (_step == 1) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _validating
                            ? null
                            : () => setState(() => _step = 0),
                        child: const Text('← Retour'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStepName(ColorScheme scheme) => [
        Text(
          'Bienvenue 👋',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choisissez le prénom ou pseudo que vos collègues verront dans les salons.',
          style:
              TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 14),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Votre prénom ou pseudo',
            hintText: 'Ex : Alice, Marc, AnneSo…',
            prefixIcon: Icon(Icons.person_outline_rounded),
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Champ requis';
            if (v.trim().length < 2) return 'Au moins 2 caractères';
            return null;
          },
          onFieldSubmitted: (_) => _next(),
        ),
      ];

  List<Widget> _buildStepKey(ColorScheme scheme) => [
        Text(
          'Votre clé Gemini 🔑',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Hackit utilise votre propre clé API Google Gemini. Elle est stockée uniquement sur cet appareil — jamais envoyée à nos serveurs.',
          style:
              TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 14),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined,
                  size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Obtenez une clé gratuite sur aistudio.google.com → "Get API key"',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _keyCtrl,
          autofocus: true,
          obscureText: _keyObscured,
          decoration: InputDecoration(
            labelText: 'Clé API Gemini',
            hintText: 'AIzaSy…',
            prefixIcon: const Icon(Icons.vpn_key_outlined),
            border: const OutlineInputBorder(),
            errorText: _keyError,
            suffixIcon: IconButton(
              icon:
                  Icon(_keyObscured ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _keyObscured = !_keyObscured),
            ),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Clé requise';
            if (!v.trim().startsWith('AIza')) {
              return 'Une clé Gemini commence par "AIza"';
            }
            return null;
          },
          onFieldSubmitted: (_) => _next(),
        ),
      ];
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  const _StepDot({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = (active || done) ? scheme.primary : scheme.outlineVariant;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active ? scheme.primary : Colors.transparent,
        border: Border.all(color: color, width: 2),
        shape: BoxShape.circle,
      ),
      child: done
          ? Icon(Icons.check, size: 16, color: scheme.primary)
          : active
              ? null
              : null,
    );
  }
}
