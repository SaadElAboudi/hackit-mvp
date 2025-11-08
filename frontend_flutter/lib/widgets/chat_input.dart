import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';

class ChatInput extends StatefulWidget {
  final void Function(String) onSearch;
  final bool disabled;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEditLast;
  final String Function()? getLastQuery;
  const ChatInput({
    super.key,
    required this.onSearch,
    this.disabled = false,
    this.onRegenerate,
    this.onEditLast,
    this.getLastQuery,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _controller.text.trim();
    if (q.isNotEmpty && !widget.disabled) {
      widget.onSearch(q);
      _controller.clear();
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
          child: Row(
            children: [
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: _handleKey,
                  child: TextField(
                    controller: _controller,
                    // Enter simple = envoyer, Shift+Enter = nouvelle ligne géré via _handleKey
                    onSubmitted: (_) => _submit(),
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(fontSize: SizeConfig.adaptiveFontSize(14)),
                    decoration: InputDecoration(
                      hintText: 'Posez votre question…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer',
                              onPressed: () => setState(_controller.clear),
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: AdaptiveSpacing.small),
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
              SizedBox(width: AdaptiveSpacing.small),
              if (widget.onRegenerate != null)
                Tooltip(
                  message: 'Regénérer la dernière réponse',
                  child: IconButton(
                    onPressed: widget.disabled ? null : widget.onRegenerate,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              if (widget.onEditLast != null)
                Tooltip(
                  message: 'Rééditer le dernier prompt',
                  child: IconButton(
                    onPressed: widget.disabled
                        ? null
                        : () {
                            final last = widget.getLastQuery?.call();
                            if (last != null && last.isNotEmpty) {
                              setState(() {
                                _controller.text = last;
                                _controller.selection = TextSelection.collapsed(
                                    offset: last.length);
                              });
                            }
                            widget.onEditLast!();
                          },
                    icon: const Icon(Icons.edit_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
