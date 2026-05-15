import 'dart:convert';

/// 用户绑定后保存的 Server 配置
class ServerConfig {
  final String server;
  final int port;
  final String subToken;
  final String agentId;
  final String deviceName;
  final bool trustSelfSigned;

  const ServerConfig({
    required this.server,
    required this.port,
    required this.subToken,
    required this.agentId,
    required this.deviceName,
    this.trustSelfSigned = true,
  });

  ServerConfig copyWith({
    String? server,
    int? port,
    String? subToken,
    String? agentId,
    String? deviceName,
    bool? trustSelfSigned,
  }) =>
      ServerConfig(
        server: server ?? this.server,
        port: port ?? this.port,
        subToken: subToken ?? this.subToken,
        agentId: agentId ?? this.agentId,
        deviceName: deviceName ?? this.deviceName,
        trustSelfSigned: trustSelfSigned ?? this.trustSelfSigned,
      );

  Map<String, dynamic> toJson() => {
        'server': server,
        'port': port,
        'sub_token': subToken,
        'agent_id': agentId,
        'device_name': deviceName,
        'trust_self_signed': trustSelfSigned,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
        server: j['server'] as String,
        port: (j['port'] as num).toInt(),
        subToken: j['sub_token'] as String,
        agentId: (j['agent_id'] as String?) ?? '',
        deviceName: (j['device_name'] as String?) ?? 'Android',
        trustSelfSigned: (j['trust_self_signed'] as bool?) ?? true,
      );

  /// 解析 QR payload，预期形如：
  /// {"server":"cc.example.com","port":8443,"sub_token":"...","agent_id":"agt_..."}
  static ServerConfig? tryParseQr(String raw) {
    try {
      final s = raw.trim();
      if (!s.startsWith('{')) return null;
      final dynamic j = jsonDecode(s);
      if (j is! Map<String, dynamic>) return null;
      if (j['server'] == null || j['port'] == null || j['sub_token'] == null) {
        return null;
      }
      return ServerConfig(
        server: j['server'] as String,
        port: (j['port'] as num).toInt(),
        subToken: j['sub_token'] as String,
        agentId: (j['agent_id'] as String?) ?? '',
        deviceName: 'Android',
      );
    } catch (_) {
      return null;
    }
  }
}
