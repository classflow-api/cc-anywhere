import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/protocol_message.dart';
import '../models/server_config.dart';
import 'logger.dart';

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

/// Mac 在线状态（来自 server 推送）
enum MacPresence { unknown, online, offline }

class NotConnectedException implements Exception {
  const NotConnectedException();
  @override
  String toString() => 'NotConnectedException: WebSocket not connected';
}

class BindFailedException implements Exception {
  final String code;
  final String message;
  const BindFailedException(this.code, this.message);
  @override
  String toString() => 'BindFailed($code): $message';
}

/// WebSocket 客户端
///
/// 职责：
/// 1. 连接 wss + 发 bind + 等 bind.ack
/// 2. 重连（1s/3s/10s/30s 指数退避）
/// 3. 心跳 ping (15s)
/// 4. 入站 stream → 解码 → 广播
/// 5. Mac presence 状态变量
class WsClient {
  WsClient(this._log);

  final AppLogger _log;
  final _uuid = const Uuid();

  WebSocketChannel? _channel;
  ServerConfig? _config;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _presenceController = StreamController<MacPresence>.broadcast();
  final _inbound = StreamController<ProtocolMessage>.broadcast();

  WsConnectionState _state = WsConnectionState.disconnected;
  MacPresence _macPresence = MacPresence.unknown;
  int _reconnectAttempt = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  StreamSubscription<dynamic>? _channelSub;
  bool _userDisconnected = false;

  Stream<WsConnectionState> get stateStream => _stateController.stream;
  Stream<MacPresence> get presenceStream => _presenceController.stream;
  Stream<ProtocolMessage> get inbound => _inbound.stream;
  WsConnectionState get state => _state;
  MacPresence get macPresence => _macPresence;
  ServerConfig? get currentConfig => _config;

  /// 主动连接；config 已持久化的场景每次启动调用一次
  Future<void> connect(ServerConfig config) async {
    _userDisconnected = false;
    _config = config;
    _reconnectAttempt = 0;
    await _doConnect();
  }

  /// 主动断开（用户解绑或退出时）
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _channelSub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
    _setPresence(MacPresence.unknown);
  }

  /// 一次性 bind 测试（用于绑定流程）：连接 + bind + 等待 ack/error。
  /// 成功返回 agent_id，失败抛异常。
  Future<String> bindOnce(ServerConfig config) async {
    final completer = Completer<String>();
    StreamSubscription<ProtocolMessage>? sub;
    void cleanup() {
      sub?.cancel();
    }

    sub = inbound.listen((msg) {
      if (msg.type == ProtocolType.bindAck) {
        final agentId = (msg.data['agent_id'] as String?) ?? '';
        cleanup();
        if (!completer.isCompleted) completer.complete(agentId);
      } else if (msg.type == ProtocolType.bindError) {
        final code = (msg.data['code'] as String?) ?? ProtocolErrorCode.internal;
        final message = (msg.data['message'] as String?) ?? 'bind failed';
        cleanup();
        if (!completer.isCompleted) {
          completer.completeError(BindFailedException(code, message));
        }
      }
    });

    try {
      await connect(config);
      final ackOrTimeout = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw const BindFailedException('INTERNAL', '绑定超时（10s 无响应）');
        },
      );
      return ackOrTimeout;
    } catch (e) {
      cleanup();
      rethrow;
    }
  }

  Future<void> _doConnect() async {
    final config = _config;
    if (config == null) return;
    _setState(_reconnectAttempt == 0
        ? WsConnectionState.connecting
        : WsConnectionState.reconnecting);

    try {
      final uri = Uri.parse('wss://${config.server}:${config.port}/ws');
      _log.info('WsClient', 'connecting to $uri');

      // 信任自签证书（用户在配置中显式打开）
      HttpClient httpClient = HttpClient();
      if (config.trustSelfSigned) {
        httpClient.badCertificateCallback = (_, __, ___) => true;
      }

      final channel = IOWebSocketChannel.connect(
        uri,
        pingInterval: const Duration(seconds: 15),
        customClient: httpClient,
      );
      _channel = channel;

      _channelSub = channel.stream.listen(
        _onRaw,
        onError: (Object e, StackTrace st) {
          _log.warn('WsClient', 'stream error: $e');
          _handleDisconnect();
        },
        onDone: () {
          _log.info('WsClient', 'stream done');
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      // 等待 ready 再发 bind
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _sendBind(config);
      _setState(WsConnectionState.connected);
      _reconnectAttempt = 0;
      _startHeartbeat();
    } catch (e, st) {
      _log.error('WsClient', 'connect failed', e, st);
      _handleDisconnect();
    }
  }

  Future<void> _sendBind(ServerConfig config) async {
    String model = 'Android';
    String osVersion = 'Android';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      model = info.model;
      osVersion = 'Android ${info.version.release}';
    } catch (_) {/* 模拟器或不支持 */}

    final msg = ProtocolMessage(
      type: ProtocolType.bind,
      id: _uuid.v4(),
      data: {
        'type': 'phone',
        'token': config.subToken,
        'device_name': config.deviceName,
        'device_model': model,
        'os_version': osVersion,
      },
    );
    await _rawSend(msg);
  }

  Future<void> send(ProtocolMessage msg) async {
    if (_state != WsConnectionState.connected) {
      throw const NotConnectedException();
    }
    await _rawSend(msg);
  }

  /// 等待 inbound 中第一条满足条件的协议消息。
  ///
  /// - [forTypes]：期望的 type 集合（命中任一即返回；用于同时监听成功 + 错误回包）
  /// - [matcher]：可选过滤器，进一步在 type 命中后做 data 字段匹配（用于关联请求/响应）
  /// - [timeout]：超时（默认 10s），超时抛 [TimeoutException]
  Future<ProtocolMessage> awaitResponse({
    required Set<String> forTypes,
    bool Function(ProtocolMessage msg)? matcher,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final completer = Completer<ProtocolMessage>();
    StreamSubscription<ProtocolMessage>? sub;
    Timer? timer;
    void cleanup() {
      timer?.cancel();
      sub?.cancel();
    }

    sub = inbound.listen((msg) {
      if (!forTypes.contains(msg.type)) return;
      if (matcher != null && !matcher(msg)) return;
      if (!completer.isCompleted) {
        completer.complete(msg);
        cleanup();
      }
    });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('awaitResponse timed out', timeout),
        );
        cleanup();
      }
    });

    return completer.future;
  }

  Future<void> _rawSend(ProtocolMessage msg) async {
    final raw = jsonEncode(msg.toJson());
    _channel?.sink.add(raw);
    _log.debug('WsClient', '>> ${msg.type}');
  }

  void _onRaw(dynamic data) {
    if (data is! String) return;
    try {
      final j = jsonDecode(data);
      final m = ProtocolMessage.tryFromJson(j);
      if (m == null) {
        _log.warn('WsClient', 'malformed inbound: $data');
        return;
      }
      _log.debug('WsClient', '<< ${m.type}');

      switch (m.type) {
        case ProtocolType.ping:
          _rawSend(ProtocolMessage(type: ProtocolType.pong, id: m.id));
          return;
        case ProtocolType.presenceMacOnline:
          _setPresence(MacPresence.online);
          break;
        case ProtocolType.presenceMacOffline:
          _setPresence(MacPresence.offline);
          break;
      }
      _inbound.add(m);
    } catch (e, st) {
      _log.error('WsClient', 'inbound decode error', e, st);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_state == WsConnectionState.connected) {
        _rawSend(ProtocolMessage(type: ProtocolType.ping, id: _uuid.v4()));
      }
    });
  }

  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    _channel = null;
    if (_userDisconnected) {
      _setState(WsConnectionState.disconnected);
      return;
    }
    _setState(WsConnectionState.reconnecting);
    _setPresence(MacPresence.unknown);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_userDisconnected) return;
    final delays = [1, 3, 10, 30];
    final idx = math.min(_reconnectAttempt, delays.length - 1);
    _reconnectAttempt++;
    final secs = delays[idx];
    _log.info('WsClient', 'reconnect in ${secs}s (attempt $_reconnectAttempt)');
    _reconnectTimer = Timer(Duration(seconds: secs), _doConnect);
  }

  void _setState(WsConnectionState s) {
    if (_state == s) return;
    _state = s;
    _stateController.add(s);
  }

  void _setPresence(MacPresence p) {
    if (_macPresence == p) return;
    _macPresence = p;
    _presenceController.add(p);
  }

  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _presenceController.close();
    await _inbound.close();
  }
}

final wsClientProvider = Provider<WsClient>((ref) {
  final c = WsClient(ref.read(loggerProvider));
  ref.onDispose(c.dispose);
  return c;
});

final wsConnectionStateProvider = StreamProvider<WsConnectionState>(
  (ref) => ref.watch(wsClientProvider).stateStream,
);

final macPresenceProvider = StreamProvider<MacPresence>(
  (ref) => ref.watch(wsClientProvider).presenceStream,
);
