import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

/// Claude 文本回复 — 左对齐 + Markdown
class AssistantTextCard extends StatelessWidget {
  final Message message;
  const AssistantTextCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClaudeAvatar(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Claude · ${DateFormat('HH:mm').format(message.timestamp)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.bgElev,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: t.line),
                  ),
                  child: MarkdownBody(
                    data: message.text ?? '',
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: t.text,
                        fontSize: 14,
                        height: 1.55,
                      ),
                      code: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: t.accent,
                        backgroundColor: t.accentSoft,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: t.bgInset,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      codeblockPadding: const EdgeInsets.all(10),
                      strong: TextStyle(
                          color: t.text, fontWeight: FontWeight.w700),
                      em: TextStyle(
                          color: t.text, fontStyle: FontStyle.italic),
                      a: TextStyle(color: t.accent),
                      blockquote: TextStyle(
                          color: t.textMuted, fontStyle: FontStyle.italic),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: t.line, width: 3),
                        ),
                      ),
                      h1: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 20),
                      h2: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 17),
                      h3: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaudeAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.assistantAvatarStart, t.accent],
        ),
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: t.assistantAvatarStart.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: const Icon(
        Icons.auto_awesome_rounded,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}
