import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// typing 跳点 — 3 个圆点 cc-bounce 1.2s 错峰
class TypingDots extends StatefulWidget {
  final Color? color;
  const TypingDots({super.key, this.color});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
      Future<void>.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = widget.color ?? t.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedBuilder(
            animation: _ctrls[i],
            builder: (_, __) {
              final dy = -_ctrls[i].value * 4;
              return Transform.translate(
                offset: Offset(0, dy),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
