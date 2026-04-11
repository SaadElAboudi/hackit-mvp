import 'package:flutter/material.dart';
import '../services/project_service.dart';

/// Profile & settings screen: update display name.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = ProjectService.currentDisplayName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le prénom ne peut pas être vide')),
      );
      return;
    }
    setState(() => _saving = true);
    await ProjectService.setDisplayName(name);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _successMsg = 'Profil mis à jour ✓';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _successMsg = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
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
