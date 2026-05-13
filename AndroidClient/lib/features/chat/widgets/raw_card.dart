import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

/// 无法解析的原始 JSON
class RawCard extends StatelessWidget {
  final Message message;
  const RawCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.bgInset,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.danger.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.code_rounded, size: 14, color: t.danger),
                const SizedBox(width: 6),
                Text('无法解析',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.danger,
                    )),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              message.rawLine ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: t.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
