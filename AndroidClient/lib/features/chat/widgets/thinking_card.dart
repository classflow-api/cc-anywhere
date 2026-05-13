import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

/// 思考折叠卡片 — 左侧 26px 空位（对齐 avatar），虚线边框
class ThinkingCard extends StatefulWidget {
  final Message message;
  const ThinkingCard({super.key, required this.message});

  @override
  State<ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<ThinkingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = widget.message.text ?? '';
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.bgInset,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: t.line,
                    style: BorderStyle.solid,
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
                          Icon(Icons.auto_awesome_outlined,
                              size: 14, color: t.textFaint),
                          const SizedBox(width: 8),
                          Text(
                            _expanded ? '思考' : '思考中 · ${_durationLabel(text)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
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
                            fontSize: 13,
                            color: t.textMuted,
                            height: 1.5,
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

  String _durationLabel(String t) {
    // 没有真实时长，用文本长度近似
    final secs = (t.length / 60).clamp(0.5, 99).toStringAsFixed(1);
    return '${secs}s';
  }
}
