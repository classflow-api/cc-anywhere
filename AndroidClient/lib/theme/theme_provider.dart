import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 主题模式偏好
///
/// 设计稿默认 dark；用户可在设置页切到 light / system。
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'theme_mode';
  final _storage = const FlutterSecureStorage();

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key);
      switch (v) {
        case 'light':
          state = ThemeMode.light;
          break;
        case 'system':
          state = ThemeMode.system;
          break;
        case 'dark':
        default:
          state = ThemeMode.dark;
      }
    } catch (_) {
      // 存储不可用时保持默认 dark
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await _storage.write(
        key: _key,
        value: switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
    } catch (_) {/* ignore */}
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((_) => ThemeModeNotifier());
