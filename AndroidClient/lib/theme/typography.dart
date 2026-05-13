import 'package:flutter/material.dart';

/// 字体配置
///
/// 设计稿使用 Inter / system-ui + JetBrains Mono。
/// Flutter 默认在 Android 上是 Roboto，效果接近 Inter，因此不内嵌字体文件，
/// 仅在等宽场景显式指定 monospace fallback。
class AppTypography {
  AppTypography._();

  static const String monoFontFamily = 'monospace';

  /// 等宽 TextStyle builder
  static TextStyle mono({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: monoFontFamily,
      fontFamilyFallback: const ['Courier', 'monospace'],
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// 大标题 36/800/-0.8
  static TextStyle display(Color color) => TextStyle(
        color: color,
        fontSize: 36,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.8,
      );

  /// 章节标题 30/800/-0.7
  static TextStyle title(Color color) => TextStyle(
        color: color,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: -0.7,
      );

  /// 小段标签 10.5/600/letter-spacing 1.4 uppercase
  static TextStyle sectionLabel(Color color) => TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      );

  /// 卡片标题 15/700
  static TextStyle cardTitle(Color color) => TextStyle(
        color: color,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      );

  /// 正文 14
  static TextStyle body(Color color) => TextStyle(
        color: color,
        fontSize: 14,
        height: 1.45,
      );

  /// 小字 12.5
  static TextStyle small(Color color) => TextStyle(
        color: color,
        fontSize: 12.5,
        height: 1.45,
      );

  /// 极小标签 11
  static TextStyle micro(Color color) => TextStyle(
        color: color,
        fontSize: 11,
      );
}
