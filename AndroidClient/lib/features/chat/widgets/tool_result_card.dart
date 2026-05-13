import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

class ToolResultCard extends StatefulWidget {
  final Message message;
  const ToolResultCard({super.key, required this.message});

  @override
  State<ToolResultCard> createState() => _ToolResultCardState();
}

class _ToolResultCardState extends State<ToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isError = widget.message.toolResultIsError;
    final text = widget.message.toolResultText ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 26 + 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.bgInset,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isError ? t.danger.withValues(alpha: 0.4) : t.line,
                  ),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isError
                                ? Icons.error_outline
                                : Icons.task_alt_rounded,
                            size: 14,
                            color: isError ? t.danger : t.success,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isError ? '工具结果 · 错误' : '工具结果',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.textMuted,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: t.textMuted,
                          ),
                        ],
                      ),
                      if (_expanded) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          text,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: t.textMuted,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
