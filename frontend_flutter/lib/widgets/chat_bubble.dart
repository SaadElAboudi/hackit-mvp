import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final String roleLabel;
  final IconData icon;

  const ChatBubble({
    Key? key,
    required this.content,
    required this.isUser,
    required this.roleLabel,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 6),
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        constraints: BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color:
              isUser ? Color(0xFF00C48C).withOpacity(0.12) : Color(0xFFF7F7F9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isUser
                ? Text(
                    content,
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  )
                : MarkdownBody(
                    data: content,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                  ),
            SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: isUser ? Color(0xFF00C48C) : Colors.blueGrey),
                SizedBox(width: 6),
                Text(
                  roleLabel,
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
