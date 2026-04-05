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
  final FocusNode _focusNode = FocusNode();
  String? _selectedTemplate;
  String? _selectedDeadline;
  bool _restoredToastShown = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  SearchContext _buildContext() {
    final deadline = switch (_selectedDeadline) {
      '1s' => '1 semaine',
      '2s' => '2 semaines',
      '1m' => '1 mois',
      '3m' => '3 mois',
      _ => null,
    };
    return {
      'clientType': null,
      'budget': null,
      'deadline': deadline,
      'maturity': null,
    };
  }

  void _submit() {
    final q = _controller.text.trim();
    if (q.isNotEmpty && !widget.disabled) {
      // Apply mode template to enrich query without modifying the visible input.
      String enhanced = q;
      try {
        final provider = Provider.of<SearchProvider>(context, listen: false);
        final id = _selectedTemplate ?? provider.lastTemplate;
        if (id != null) {
          enhanced = provider.applyTemplateText(id, q);
          provider.setLastTemplate(id);
        }
      } catch (_) {}

      final contextData = _buildContext();
      if (widget.onSearchWithContext != null) {
        widget.onSearchWithContext!(enhanced, contextData);
      } else {
        widget.onSearch(enhanced);
      }
      _controller.clear();
      try {
        final p = Provider.of<SearchProvider>(context, listen: false);
        p.setDraft('');
      } catch (_) {}
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
        elevation: 3,
        borderRadius: BorderRadius.circular(22),
        shadowColor: Colors.black12,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AdaptiveSpacing.medium,
              AdaptiveSpacing.medium,
              AdaptiveSpacing.small,
              AdaptiveSpacing.small,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Input + send button
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
                          minLines: 1,
                          maxLines: 6,
                          style: TextStyle(
                            fontSize: SizeConfig.adaptiveFontSize(15),
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Décris le brief client ou le livrable…',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 44,
                      width: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: widget.disabled ? null : _submit,
                        child: const Icon(Icons.arrow_upward_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                SizedBox(height: AdaptiveSpacing.small),
                // Context chips: mode + deadline in a single scrollable row
                _ContextChips(
                  selectedMode: _selectedTemplate,
                  selectedDeadline: _selectedDeadline,
                  disabled: widget.disabled,
                  onModeSelected: (id) =>
                      setState(() => _selectedTemplate = id),
                  onDeadlineSelected: (d) =>
                      setState(() => _selectedDeadline = d),
                ),
                // Edit / regenerate actions
                if (widget.onRegenerate != null || widget.onEditLast != null)
                  Padding(
                    padding: EdgeInsets.only(top: AdaptiveSpacing.tiny),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onEditLast != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                            onPressed: (widget.disabled || !hasLastQuery)
                                ? null
                                : widget.onEditLast,
                            icon: const Icon(Icons.edit_rounded, size: 15),
                            label: const Text('Modifier',
                                style: TextStyle(fontSize: 13)),
                          ),
                        if (widget.onRegenerate != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                            onPressed: (widget.disabled || !hasLastQuery)
                                ? null
                                : widget.onRegenerate,
                            icon: const Icon(Icons.refresh_rounded, size: 15),
                            label: const Text('Relancer',
                                style: TextStyle(fontSize: 13)),
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

// Single scrollable row combining mode chips + deadline chips.
class _ContextChips extends StatelessWidget {
  final String? selectedMode;
  final String? selectedDeadline;
  final bool disabled;
  final void Function(String?) onModeSelected;
  final void Function(String?) onDeadlineSelected;

  const _ContextChips({
    required this.selectedMode,
    required this.selectedDeadline,
    required this.disabled,
    required this.onModeSelected,
    required this.onDeadlineSelected,
  });

  static const _modes = [
    ('cadrer', '⚡ Cadrer'),
    ('produire', '🔨 Produire'),
    ('communiquer', '📣 Communiquer'),
    ('audit', '🔍 Audit 7j'),
  ];

  static const _deadlines = [
    ('1s', '1 sem'),
    ('2s', '2 sem'),
    ('1m', '1 mois'),
    ('3m', '3 mois'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const chipText = TextStyle(fontSize: 12);
    const chipPad = EdgeInsets.symmetric(horizontal: 6, vertical: 0);
    const density = VisualDensity.compact;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (id, label) in _modes) ...[
            FilterChip(
              label: Text(label, style: chipText),
              selected: selectedMode == id,
              onSelected:
                  disabled ? null : (v) => onModeSelected(v ? id : null),
              visualDensity: density,
              padding: chipPad,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 5),
          ],
          // Divider
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 1,
            height: 18,
            color: scheme.outlineVariant,
          ),
          Text(
            'Délai',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 6),
          for (final (id, label) in _deadlines) ...[
            ChoiceChip(
              label: Text(label, style: chipText),
              selected: selectedDeadline == id,
              onSelected:
                  disabled ? null : (v) => onDeadlineSelected(v ? id : null),
              visualDensity: density,
              padding: chipPad,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}
