import 'dart:ui';

import 'package:flutter/material.dart';

/// 极光 orb 背景 — 1:1 对应 shared.jsx AuroraOrbs
///
/// 3 个大圆 + ImageFilter.blur(80) + 18-28s 漂移动画
class AuroraOrbs extends StatefulWidget {
  final List<Color> palette;

  /// 默认 cyan 配色 — oklch(0.72 0.18 200 / 0.5) 等
  AuroraOrbs({super.key, List<Color>? palette})
      : palette = palette ??
            [
              const Color(0x8044C4DD), // ~oklch(0.72 0.18 200 / 0.5)
              const Color(0x6655CFA1), // ~oklch(0.78 0.14 170 / 0.4)
              const Color(0x664F7BE0), // ~oklch(0.65 0.16 240 / 0.4)
            ];

  @override
  State<AuroraOrbs> createState() => _AuroraOrbsState();
}

class _AuroraOrbsState extends State<AuroraOrbs> with TickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);
  late final AnimationController _b = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  )..repeat(reverse: true);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            _orb(_a, widget.palette[0],
                anchor: const Alignment(-1.1, -1.2), size: 520, drift: 40),
            _orb(_b, widget.palette[1],
                anchor: const Alignment(1.2, 1.2), size: 460, drift: 36),
            _orb(_c, widget.palette[2],
                anchor: const Alignment(0.8, -0.3), size: 320, drift: 30),
          ],
        ),
      ),
    );
  }

  Widget _orb(
    AnimationController ctrl,
    Color color, {
    required Alignment anchor,
    required double size,
    required double drift,
  }) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = ctrl.value; // 0..1
        final dx = (t - 0.5) * 2 * drift;
        final dy = (t - 0.5) * 2 * drift;
        return Align(
          alignment: anchor,
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
