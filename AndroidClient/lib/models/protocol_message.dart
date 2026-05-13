/// WebSocket envelope
///
/// 协议见需求规格说明书 §3.4。统一形如：
/// `{"type": "...", "id": "uuid", "data": {...}}`
class ProtocolMessage {
  final String type;
  final String id;
  final Map<String, dynamic> data;

  const ProtocolMessage({
    required this.type,
    required this.id,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'data': data,
      };

  static ProtocolMessage? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final type = m['type'];
    final id = m['id'];
    if (type is! String || id is! String) return null;
    final data = m['data'];
    return ProtocolMessage(
      type: type,
      id: id,
      data: data is Map ? data.cast<String, dynamic>() : <String, dynamic>{},
    );
  }
}

/// 协议消息类型常量
abstract class ProtocolType {
  // 鉴权
  static const bind = 'bind';
  static const bindAck = 'bind.ack';
  static const bindError = 'bind.error';
  static const ping = 'ping';
  static const pong = 'pong';
  static const forceDisconnect = 'force_disconnect';

  // 设备
  static const deviceSelfUnbind = 'device.self_unbind';

  // Tab
  static const tabList = 'tab.list';
  static const tabListRequest = 'tab.list.request';
  static const tabListResponse = 'tab.list.response';
  static const tabChanged = 'tab.changed';

  // 消息
  static const msgStream = 'msg.stream';
  static const msgHistoryRequest = 'msg.history.request';
  static const msgHistoryResponse = 'msg.history.response';
  static const msgRaw = 'msg.raw';

  // 输入
  static const inputText = 'input.text';
  static const inputError = 'input.error';
  static const imageUploadBegin = 'image.upload.begin';
  static const imageUploadUrl = 'image.upload.url';
  static const imageUploadExpired = 'image.upload.expired';
  static const toolUseApprove = 'tool_use.approve';

  // presence
  static const presenceMacOnline = 'presence.mac_online';
  static const presenceMacOffline = 'presence.mac_offline';
  static const presencePhoneCount = 'presence.phone_count';
}

/// 错误码常量
abstract class ProtocolErrorCode {
  static const invalidToken = 'INVALID_TOKEN';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const revoked = 'REVOKED';
  static const macOffline = 'MAC_OFFLINE';
  static const tabNotFound = 'TAB_NOT_FOUND';
  static const imageTooLarge = 'IMAGE_TOO_LARGE';
  static const sha256Mismatch = 'SHA256_MISMATCH';
  static const internal = 'INTERNAL';
}
