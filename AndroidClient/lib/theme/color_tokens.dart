import 'package:flutter/material.dart';

/// Design tokens — 1:1 from `UI设计稿/cc-anywhere/project/tokens.js`
///
/// 由于 Flutter 不支持原生 oklch()，所有 oklch 值都已经过设计稿渲染对比，
/// 在 sRGB 空间下用最接近的视觉等效值落地。
class ColorTokens {
  final Color bg;
  final Color bgElev;
  final Color bgInset;
  final Color panel;
  final Color line;
  final Color lineStrong;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color accentSoft;
  final Color accentFg;
  final Color success;
  final Color warn;
  final Color danger;
  final Color glassTint;
  final Color dotGrid;

  const ColorTokens({
    required this.bg,
    required this.bgElev,
    required this.bgInset,
    required this.panel,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentSoft,
    required this.accentFg,
    required this.success,
    required this.warn,
    required this.danger,
    required this.glassTint,
    required this.dotGrid,
  });

  /// 浅色主题 — 来自 tokens.js light
  /// bg #f4f3ee, bgElev #ffffff, bgInset #ece9e1
  /// accent oklch(0.62 0.13 215) ~ #4e9cb9
  static const ColorTokens light = ColorTokens(
    bg: Color(0xFFF4F3EE),
    bgElev: Color(0xFFFFFFFF),
    bgInset: Color(0xFFECE9E1),
    panel: Color(0xB3FFFFFF), // rgba(255,255,255,0.7)
    line: Color(0x140F172A), // rgba(15,23,42,0.08)
    lineStrong: Color(0x240F172A), // rgba(15,23,42,0.14)
    text: Color(0xFF0C111C),
    textMuted: Color(0xFF4F5666),
    textFaint: Color(0xFF8A8F9C),
    accent: Color(0xFF4E9CB9), // oklch(0.62 0.13 215)
    accentSoft: Color(0xFFD4ECF3), // oklch(0.92 0.06 215)
    // accentFg：accent 背景上的对比文字色。accent + accentGradEnd 是深蓝绿渐变，
    // 必须用白色才有足够对比度（之前误用深蓝 0xFF0A2433 导致用户气泡里的文字与
    // 发送按钮图标在浅色模式下几乎黑色，看不清）。
    accentFg: Color(0xFFFFFFFF),
    success: Color(0xFF1FAF6A), // oklch(0.65 0.15 155)
    warn: Color(0xFFE2A338), // oklch(0.78 0.16 70)
    danger: Color(0xFFD9483A), // oklch(0.62 0.20 25)
    glassTint: Color(0x8CFFFFFF), // rgba(255,255,255,0.55)
    dotGrid: Color(0x0F0F172A), // rgba(15,23,42,0.06)
  );

  /// 深色主题 — 来自 tokens.js dark（项目默认）
  /// bg #0b0e14, bgElev #11151d, bgInset #070910
  /// accent oklch(0.78 0.13 200) ~ #59CFE7
  static const ColorTokens dark = ColorTokens(
    bg: Color(0xFF0B0E14),
    bgElev: Color(0xFF11151D),
    bgInset: Color(0xFF070910),
    panel: Color(0x99141A24), // rgba(20,26,36,0.6)
    line: Color(0x12FFFFFF), // rgba(255,255,255,0.07)
    lineStrong: Color(0x24FFFFFF), // rgba(255,255,255,0.14)
    text: Color(0xFFE9EDF5),
    textMuted: Color(0xFF9098A8),
    textFaint: Color(0xFF5A6172),
    accent: Color(0xFF59CFE7), // oklch(0.78 0.13 200)
    accentSoft: Color(0xFF1B3742), // oklch(0.30 0.08 200)
    accentFg: Color(0xFFE9F7FB),
    success: Color(0xFF52DBA5), // oklch(0.78 0.16 155)
    warn: Color(0xFFEAB349), // oklch(0.82 0.16 75)
    danger: Color(0xFFEC6C5F), // oklch(0.72 0.20 25)
    glassTint: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    dotGrid: Color(0x0DFFFFFF),
  );

  /// 用于 user 气泡背景上的渐变副色 oklch(0.6 0.16 240)
  Color get accentGradEnd =>
      this == dark ? const Color(0xFF4F7BE6) : const Color(0xFF3D6BD4);

  /// Claude 头像渐变副色 oklch(0.7 0.18 280)
  Color get assistantAvatarStart =>
      this == dark ? const Color(0xFFA68BFF) : const Color(0xFF8B6FE0);
}

/// 全局扩展：从 BuildContext 拿到 ColorTokens
extension TokensX on BuildContext {
  ColorTokens get tokens =>
      Theme.of(this).brightness == Brightness.dark
          ? ColorTokens.dark
          : ColorTokens.light;
}
