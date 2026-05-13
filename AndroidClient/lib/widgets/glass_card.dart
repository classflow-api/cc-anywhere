import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';

/// 玻璃卡片 — 1:1 对应 shared.jsx GlassCard
///
/// 背景 var(--panel) + backdrop-filter: blur(20px) saturate(160%).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final bool glow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius:
          borderRadius is BorderRadius ? borderRadius as BorderRadius : BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: borderRadius,
            border: Border.all(color: t.line),
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: t.accent.withValues(alpha: 0.3),
                      blurRadius: 36,
                      offset: const Offset(0, 12),
                      spreadRadius: -12,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// SectionLabel — 小段标签
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry? padding;
  const SectionLabel(this.text, {super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final child = Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        color: t.textFaint,
      ),
    );
    return padding != null ? Padding(padding: padding!, child: child) : child;
  }
}
