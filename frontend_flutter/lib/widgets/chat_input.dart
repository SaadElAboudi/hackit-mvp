// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';
import 'package:provider/provider.dart';
import '../providers/search_provider.dart';

typedef SearchContext = Map<String, String?>;

class ChatInput extends StatefulWidget {
  final void Function(String) onSearch;
  final void Function(String, SearchContext)? onSearchWithContext;
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
    this.onSearchWithContext,
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
  final TextEditingController _clientTypeController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _deadlineController = TextEditingController();
  final TextEditingController _maturityController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _selectedTemplate; // local UI state
  bool _restoredToastShown = false;
  bool _showContextFields = false;

  @override
  void dispose() {
    _controller.dispose();
    _clientTypeController.dispose();
    _budgetController.dispose();
    _deadlineController.dispose();
    _maturityController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  SearchContext _buildContext() {
    String? norm(String value) {
      final v = value.trim();
      return v.isEmpty ? null : v;
    }

    return {
      'clientType': norm(_clientTypeController.text),
      'budget': norm(_budgetController.text),
      'deadline': norm(_deadlineController.text),
      'maturity': norm(_maturityController.text),
    };
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

      final contextData = _buildContext();
      if (widget.onSearchWithContext != null) {
        widget.onSearchWithContext!(q, contextData);
      } else {
        widget.onSearch(q);
      }
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
    final lastQuery = (widget.getLastQuery?.call() ?? '').trim();
    final hasLastQuery = lastQuery.isNotEmpty;
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
      padding: EdgeInsets.fromLTRB(
        AdaptiveSpacing.large,
        AdaptiveSpacing.small,
        AdaptiveSpacing.large,
        AdaptiveSpacing.medium,
      ),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(22),
        shadowColor: Colors.black12,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.25),
              width: 1.1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AdaptiveSpacing.large,
              vertical: AdaptiveSpacing.medium,
            ),
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
                          _controller.selection = TextSelection.collapsed(
                              offset: transformed.length);
                        });
                      }
                      _focusNode.requestFocus();
                    },
                  ),
                  SizedBox(height: AdaptiveSpacing.small),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.disabled
                        ? null
                        : () => setState(
                            () => _showContextFields = !_showContextFields),
                    icon: Icon(_showContextFields
                        ? Icons.tune_rounded
                        : Icons.tune_outlined),
                    label: Text(_showContextFields
                        ? 'Masquer le contexte'
                        : 'Contexte client'),
                  ),
                ),
                if (_showContextFields) ...[
                  SizedBox(height: AdaptiveSpacing.tiny),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ContextField(
                        controller: _clientTypeController,
                        label: 'Type client',
                        hint: 'Startup, PME, grand compte',
                      ),
                      _ContextField(
                        controller: _budgetController,
                        label: 'Budget',
                        hint: 'Faible / Moyen / Élevé',
                      ),
                      _ContextField(
                        controller: _deadlineController,
                        label: 'Deadline',
                        hint: 'Ex: 2 semaines',
                      ),
                      _ContextField(
                        controller: _maturityController,
                        label: 'Maturité',
                        hint: 'Débutant / Intermédiaire / Avancé',
                      ),
                    ],
                  ),
                  SizedBox(height: AdaptiveSpacing.small),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                              fontSize: SizeConfig.adaptiveFontSize(15),
                              color: Colors.black),
                          minLines: 1,
                          maxLines: 6,
                          decoration: InputDecoration(
                            hintText:
                                'Décris le brief client ou le livrable à produire…',
                            suffixIcon: null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                      onPressed: widget.disabled ? null : _submit,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send_rounded, size: 22),
                          SizedBox(width: 8),
                          Text('Générer',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.onRegenerate != null || widget.onEditLast != null)
                  Padding(
                    padding: EdgeInsets.only(top: AdaptiveSpacing.small),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.onEditLast != null)
                          OutlinedButton.icon(
                            onPressed: (widget.disabled || !hasLastQuery)
                                ? null
                                : widget.onEditLast,
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('Modifier'),
                          ),
                        if (widget.onRegenerate != null)
                          OutlinedButton.icon(
                            onPressed: (widget.disabled || !hasLastQuery)
                                ? null
                                : widget.onRegenerate,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Relancer'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
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
      ('cadrer', 'Cadrer'),
      ('produire', 'Produire'),
      ('communiquer', 'Communiquer'),
      ('audit', 'Audit 7j'),
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

class _ContextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _ContextField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final fieldWidth = width < 700 ? width - 96 : (width - 180) / 2;
    return SizedBox(
      width: fieldWidth.clamp(220.0, 420.0),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
