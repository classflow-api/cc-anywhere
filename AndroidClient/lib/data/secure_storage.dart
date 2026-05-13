import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/server_config.dart';
import 'logger.dart';

/// 加密存储封装（基于 flutter_secure_storage / Keystore）
class SecureStorage {
  SecureStorage(this._log);

  static const _kConfig = 'cc_anywhere.config_v1';

  final AppLogger _log;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<ServerConfig?> readConfig() async {
    try {
      final raw = await _storage.read(key: _kConfig);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      return ServerConfig.fromJson(j);
    } catch (e, st) {
      _log.error('SecureStorage', 'readConfig failed', e, st);
      return null;
    }
  }

  Future<void> writeConfig(ServerConfig config) async {
    await _storage.write(key: _kConfig, value: jsonEncode(config.toJson()));
    _log.info('SecureStorage', 'config saved');
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
    _log.info('SecureStorage', 'all cleared');
  }
}

final secureStorageProvider = Provider<SecureStorage>(
  (ref) => SecureStorage(ref.read(loggerProvider)),
);
