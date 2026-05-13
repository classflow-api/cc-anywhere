import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import 'pulse_dot.dart';

/// 状态药丸 — 1:1 对应 shared.jsx StatusPill
class StatusPill extends StatelessWidget {
  final Color? dotColor;
  final Widget? icon;
  final String text;
  final bool accent;

  const StatusPill({
    super.key,
    this.dotColor,
    this.icon,
    required this.text,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            PulseDot(color: dotColor!, size: 6, pulse: accent),
            const SizedBox(width: 4),
          ],
          if (icon != null) ...[icon!, const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: t.textMuted,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
