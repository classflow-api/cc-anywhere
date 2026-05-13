import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'color_tokens.dart';

class AppThemeData {
  AppThemeData._();

  static ThemeData build({required Brightness brightness}) {
    final t = brightness == Brightness.dark ? ColorTokens.dark : ColorTokens.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.accentFg,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.accent,
      secondary: t.accent,
      onSecondary: t.accentFg,
      error: t.danger,
      onError: Colors.white,
      surface: t.bgElev,
      onSurface: t.text,
      surfaceContainerHighest: t.bgInset,
      onSurfaceVariant: t.textMuted,
      outline: t.lineStrong,
      outlineVariant: t.line,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      splashFactory: InkSparkle.splashFactory,
      // 文本输入框默认底色透明，由 InputBar 自定义
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.accent, width: 1.4),
        ),
        hintStyle: TextStyle(color: t.textFaint, fontSize: 14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: t.text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: t.textMuted, size: 22),
      textTheme: _buildTextTheme(t),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.accentFg,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.text,
          side: BorderSide(color: t.lineStrong),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: t.accent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.bgInset,
      ),
      cardTheme: CardTheme(
        color: t.bgElev,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: t.line),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.bgElev,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: t.bgElev,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.bgInset,
        contentTextStyle: TextStyle(color: t.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static TextTheme _buildTextTheme(ColorTokens t) {
    return TextTheme(
      displayLarge: TextStyle(color: t.text, fontSize: 36, fontWeight: FontWeight.w800, height: 1.05),
      displayMedium: TextStyle(color: t.text, fontSize: 30, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: t.text, fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(color: t.text, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: t.textMuted, fontSize: 12.5, height: 1.45),
      labelLarge: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: t.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(color: t.textFaint, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.4),
    );
  }
}
