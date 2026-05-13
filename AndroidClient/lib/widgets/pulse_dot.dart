import 'package:flutter/material.dart';

/// 状态脉动小圆点 — 1:1 对应 shared.jsx PulseDot
///
/// 外圈 opacity 0.4 + animation cc-pulse 1.6s ease-out 缩放 0.6→2.4。
/// 内圈固定带 boxShadow glow。
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;

  const PulseDot({
    super.key,
    required this.color,
    this.size = 8,
    this.pulse = true,
  });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.pulse) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulse)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final t = _ctrl.value; // 0..1
                final scale = 0.6 + t * 1.8;
                final opacity = (1 - t) * 0.4;
                return IgnorePointer(
                  child: Container(
                    width: (size + 4) * scale,
                    height: (size + 4) * scale,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: opacity),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
