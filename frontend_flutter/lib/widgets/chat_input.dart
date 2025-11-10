// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';
import 'package:provider/provider.dart';
import '../providers/search_provider.dart';

class ChatInput extends StatefulWidget {
  final void Function(String) onSearch;
  final bool disabled;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEditLast;
  final String Function()? getLastQuery;
  // Whether the input field should be cleared after sending a query.
  // Default: false to preserve the last prompt for visibility & easy editing.
  final bool clearOnSend;
  // Show prompt template chips (used in tests or power-user mode)
  final bool showTemplates;
  const ChatInput({
    super.key,
    required this.onSearch,
    this.disabled = false,
    this.onRegenerate,
    this.onEditLast,
    this.getLastQuery,
    this.clearOnSend = true,
    this.showTemplates = false,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  // Feature flag: show/hide prompt template chips above the input.
  // Read from widget.showTemplates.
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _selectedTemplate; // local UI state
  bool _restoredToastShown = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    String q = _controller.text.trim();
    if (q.isNotEmpty && !widget.disabled) {
      // Apply selected template at submission time to guarantee payload transformation.
      try {
        final provider = Provider.of<SearchProvider>(context, listen: false);
        final id = _selectedTemplate ?? provider.lastTemplate;
        if (id != null) {
          q = provider.applyTemplateText(id, q);
          _controller.text = q;
          _controller.selection =
              TextSelection.collapsed(offset: _controller.text.length);
        }
      } catch (_) {}

      widget.onSearch(q);
      // Toujours vider le champ après envoi pour UX plus propre.
      _controller.clear();
      try {
        // Si SearchProvider est disponible, vider aussi le draft global
        final p = Provider.of<SearchProvider>(context, listen: false);
        p.setDraft('');
      } catch (_) {}
      _selectedTemplate = null; // reset template selection after send
      // Optionnel: retirer le focus pour signaler la soumission
      _focusNode.unfocus();
    }
  }

  void _handleKey(KeyEvent e) {
    if (widget.disabled) return;
    if (e is KeyDownEvent) {
      final isMeta = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard
              .instance.isControlPressed; // Cmd(Mac) / Ctrl(Win/Linux)
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (isMeta && e.logicalKey.keyLabel.toLowerCase() == 'enter') {
        _submit();
      } else if (isShift && e.logicalKey.keyLabel.toLowerCase() == 'enter') {
        // Insert newline
        final selection = _controller.selection;
        final text = _controller.text;
        final newText = text.replaceRange(selection.start, selection.end, '\n');
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.start + 1),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig.ensureInitialized(context);
    final scheme = Theme.of(context).colorScheme;
    // Consume draft text from provider to prefill & focus when requested from a message action.
    // Provider is optional so ChatInput can be tested/rendered standalone.
    SearchProvider? provider;
    try {
      provider = Provider.of<SearchProvider>(context, listen: true);
    } catch (_) {
      provider = null;
    }
    final draft = provider?.draftText;
    if (draft != null && draft != _controller.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _controller.text = draft;
          _controller.selection = TextSelection.collapsed(offset: draft.length);
          _focusNode.requestFocus();
        });
        // Don't clear draft here; it's a persistent draft. Just show toast once.
        if (!_restoredToastShown && (provider?.draftRestored ?? false)) {
          _restoredToastShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Brouillon restauré')),
          );
          provider?.consumeDraftRestoredFlag();
        }
      });
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AdaptiveSpacing.large,
        vertical: AdaptiveSpacing.small,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: 0.05),
              scheme.primaryContainer.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(AdaptiveSpacing.small),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showTemplates) ...[
                _TemplateChips(
                  selected: _selectedTemplate ?? provider?.lastTemplate,
                  onSelected: (id) {
                    setState(() => _selectedTemplate = id);
                    provider?.setLastTemplate(id);
                    if (id != null) {
                      final transformed =
                          provider?.applyTemplateText(id, _controller.text) ??
                              _controller.text;
                      setState(() {
                        _controller.text = transformed;
                        _controller.selection =
                            TextSelection.collapsed(offset: transformed.length);
                      });
                    }
                    _focusNode.requestFocus();
                  },
                ),
                SizedBox(height: AdaptiveSpacing.small),
              ],
              Row(
                children: [
                  Expanded(
                    child: KeyboardListener(
                      focusNode: _focusNode,
                      onKeyEvent: _handleKey,
                      child: TextField(
                        controller: _controller,
                        onChanged: (v) => provider?.setDraft(v),
                        onSubmitted: (_) => _submit(),
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                            fontSize: SizeConfig.adaptiveFontSize(14)),
                        decoration: InputDecoration(
                          hintText: 'Posez votre question…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          // Plus de croix: le champ se vide automatiquement après envoi.
                          suffixIcon: null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: widget.disabled ? null : _submit,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded),
                        SizedBox(width: 8),
                        Text('Rechercher'),
                      ],
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

class _TemplateChips extends StatelessWidget {
  final String? selected;
  final void Function(String?) onSelected;
  const _TemplateChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const templates = [
      ('resume', 'Résumé'),
      ('tutoriel', 'Tutoriel'),
      ('eli5', 'ELI5'),
      ('fr2en', 'FR→EN'),
      ('en2fr', 'EN→FR'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final (id, label) in templates)
          ChoiceChip(
            label: Text(label),
            selected: selected == id,
            onSelected: (v) => onSelected(v ? id : null),
          ),
      ],
    );
  }
}
