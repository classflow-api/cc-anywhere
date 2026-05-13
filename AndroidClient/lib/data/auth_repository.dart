import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/protocol_message.dart';
import '../models/server_config.dart';
import 'logger.dart';
import 'secure_storage.dart';
import 'ws_client.dart';

/// 绑定状态
enum AuthState { unknown, bound, unbound }

class AuthRepository {
  AuthRepository(this._ref, this._storage, this._ws, this._log);

  // ignore: unused_field
  final Ref _ref;
  final SecureStorage _storage;
  final WsClient _ws;
  final AppLogger _log;

  /// 加载已绑定的配置；首次启动返回 null
  Future<ServerConfig?> loadConfig() => _storage.readConfig();

  /// 扫码或手动输入后调用：保存 config + 建立 WS
  Future<ServerConfig> completeBind(ServerConfig config) async {
    _log.info('Auth', 'bind start: ${config.server}:${config.port}');
    final agentId = await _ws.bindOnce(config);
    final saved = config.copyWith(agentId: agentId);
    await _storage.writeConfig(saved);
    _log.info('Auth', 'bind ok, agent=$agentId');
    return saved;
  }

  /// 解绑：先发 device.self_unbind 通知 Server，再清空本地
  Future<void> selfUnbind() async {
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.deviceSelfUnbind,
        id: _idGen(),
      ));
    } catch (e) {
      _log.warn('Auth', 'self_unbind send failed: $e');
    }
    await _ws.disconnect();
    await _storage.clearAll();
    _log.info('Auth', 'self unbound');
  }

  String _idGen() => DateTime.now().microsecondsSinceEpoch.toString();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref,
    ref.read(secureStorageProvider),
    ref.read(wsClientProvider),
    ref.read(loggerProvider),
  );
});

/// App 启动时尝试加载已保存的 config
final initialConfigProvider = FutureProvider<ServerConfig?>((ref) async {
  return ref.read(authRepositoryProvider).loadConfig();
});
