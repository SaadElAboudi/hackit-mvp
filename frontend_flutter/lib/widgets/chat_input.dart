import 'package:flutter/material.dart';
import '../core/responsive/adaptive_spacing.dart';
import '../core/responsive/size_config.dart';

class ChatInput extends StatefulWidget {
  final void Function(String) onSearch;
  final bool disabled;
  const ChatInput({super.key, required this.onSearch, this.disabled = false});

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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AdaptiveSpacing.large,
        vertical: AdaptiveSpacing.small,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: SizeConfig.adaptiveFontSize(14)),
              decoration: InputDecoration(
                hintText: 'Posez votre question…',
                prefixIcon: const Icon(Icons.search),
                hintStyle: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          SizedBox(width: AdaptiveSpacing.small),
          ElevatedButton.icon(
            onPressed: widget.disabled ? null : _submit,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Rechercher'),
          )
        ],
      ),
    );
  }
}
