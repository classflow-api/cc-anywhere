/// 消息 model — 由 JSONL 行解析后的统一对象
///
/// 设计参考 Claude Code JSONL：
/// - 顶层有 `role` (user/assistant) + `content` 数组
/// - content[i].type ∈ text / thinking / tool_use / tool_result / image
///
/// 我们把每个 content 项拆成单独的 Message 卡片，由 ChatRepository 排序。
enum MessageRole { user, assistant, system, unknown }

enum MessageKind {
  text,
  thinking,
  toolUse,
  toolResult,
  attachment,
  raw,
}

enum ToolUseStatus { pending, approved, rejected, executed }

class Message {
  final String uuid;
  final MessageRole role;
  final MessageKind kind;
  final DateTime timestamp;

  /// text/thinking/raw 用
  final String? text;

  /// tool_use 用
  final String? toolName;
  final Map<String, dynamic>? toolInput;
  final ToolUseStatus toolStatus;
  final String? toolUseId;

  /// tool_result 用
  final String? toolUseRefId;
  final String? toolResultText;
  final bool toolResultIsError;

  /// attachment / image 用
  final String? attachmentFilename;
  final String? attachmentLocalPath;
  final String? attachmentRemoteUrl;
  final int? attachmentSizeBytes;
  final double? uploadProgress; // 0..1
  final String? uploadError;

  /// 本地未发送 / 失败状态
  final bool isLocalPending;
  final bool sendFailed;

  /// 当 raw 解析失败时，保留原始 JSON 行
  final String? rawLine;

  const Message({
    required this.uuid,
    required this.role,
    required this.kind,
    required this.timestamp,
    this.text,
    this.toolName,
    this.toolInput,
    this.toolStatus = ToolUseStatus.pending,
    this.toolUseId,
    this.toolUseRefId,
    this.toolResultText,
    this.toolResultIsError = false,
    this.attachmentFilename,
    this.attachmentLocalPath,
    this.attachmentRemoteUrl,
    this.attachmentSizeBytes,
    this.uploadProgress,
    this.uploadError,
    this.isLocalPending = false,
    this.sendFailed = false,
    this.rawLine,
  });

  Message copyWith({
    String? text,
    ToolUseStatus? toolStatus,
    String? toolResultText,
    bool? toolResultIsError,
    double? uploadProgress,
    String? uploadError,
    bool? isLocalPending,
    bool? sendFailed,
  }) =>
      Message(
        uuid: uuid,
        role: role,
        kind: kind,
        timestamp: timestamp,
        text: text ?? this.text,
        toolName: toolName,
        toolInput: toolInput,
        toolStatus: toolStatus ?? this.toolStatus,
        toolUseId: toolUseId,
        toolUseRefId: toolUseRefId,
        toolResultText: toolResultText ?? this.toolResultText,
        toolResultIsError: toolResultIsError ?? this.toolResultIsError,
        attachmentFilename: attachmentFilename,
        attachmentLocalPath: attachmentLocalPath,
        attachmentRemoteUrl: attachmentRemoteUrl,
        attachmentSizeBytes: attachmentSizeBytes,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        uploadError: uploadError ?? this.uploadError,
        isLocalPending: isLocalPending ?? this.isLocalPending,
        sendFailed: sendFailed ?? this.sendFailed,
        rawLine: rawLine,
      );

  /// 从 JSONL 解析单行
  ///
  /// 支持两种结构：
  /// 1. {uuid, role, type:"text", text, timestamp}
  /// 2. {uuid, role, content:[{type, ...}], timestamp} — 取第一个 content 项
  /// 解析失败返回 raw kind
  static List<Message> fromRaw(Map<String, dynamic> raw) {
    try {
      final uuid = (raw['uuid'] as String?) ?? (raw['id'] as String?);
      final ts = _parseTs(raw['timestamp'] ?? raw['created_at']);
      final role = _parseRole(raw['role'] as String?);

      // 形式 1：扁平
      if (raw['content'] is! List && raw['type'] != null) {
        final m = _parseSingle(
          uuid: uuid ?? _fallbackUuid(raw),
          role: role,
          timestamp: ts,
          item: raw,
        );
        return [m];
      }

      // 形式 2：content 数组
      final content = raw['content'];
      if (content is List && content.isNotEmpty) {
        final out = <Message>[];
        for (var i = 0; i < content.length; i++) {
          final item = content[i];
          if (item is! Map<String, dynamic>) continue;
          final partUuid =
              '${uuid ?? _fallbackUuid(raw)}#$i';
          out.add(_parseSingle(
            uuid: partUuid,
            role: role,
            timestamp: ts,
            item: item,
          ));
        }
        if (out.isNotEmpty) return out;
      }

      // 形式 3：纯文本字段
      if (raw['text'] is String) {
        return [
          Message(
            uuid: uuid ?? _fallbackUuid(raw),
            role: role,
            kind: MessageKind.text,
            timestamp: ts,
            text: raw['text'] as String,
          ),
        ];
      }

      // fallback：raw
      return [
        Message(
          uuid: uuid ?? _fallbackUuid(raw),
          role: role,
          kind: MessageKind.raw,
          timestamp: ts,
          rawLine: raw.toString(),
        ),
      ];
    } catch (_) {
      return [
        Message(
          uuid: _fallbackUuid(raw),
          role: MessageRole.unknown,
          kind: MessageKind.raw,
          timestamp: DateTime.now(),
          rawLine: raw.toString(),
        ),
      ];
    }
  }

  static Message _parseSingle({
    required String uuid,
    required MessageRole role,
    required DateTime timestamp,
    required Map<String, dynamic> item,
  }) {
    final type = item['type'] as String?;
    switch (type) {
      case 'text':
        return Message(
          uuid: uuid,
          role: role,
          kind: MessageKind.text,
          timestamp: timestamp,
          text: (item['text'] as String?) ?? '',
        );
      case 'thinking':
        return Message(
          uuid: uuid,
          role: role,
          kind: MessageKind.thinking,
          timestamp: timestamp,
          text: (item['thinking'] as String?) ?? (item['text'] as String?) ?? '',
        );
      case 'tool_use':
        return Message(
          uuid: uuid,
          role: role,
          kind: MessageKind.toolUse,
          timestamp: timestamp,
          toolName: item['name'] as String?,
          toolInput: (item['input'] as Map?)?.cast<String, dynamic>(),
          toolUseId: item['id'] as String?,
          toolStatus: _parseToolStatus(item['status'] as String?),
        );
      case 'tool_result':
        final raw = item['content'];
        String? content;
        if (raw is String) {
          content = raw;
        } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
          final first = (raw.first as Map).cast<String, dynamic>();
          content = first['text'] as String?;
        }
        return Message(
          uuid: uuid,
          role: role,
          kind: MessageKind.toolResult,
          timestamp: timestamp,
          toolUseRefId: item['tool_use_id'] as String?,
          toolResultText: content ?? '',
          toolResultIsError: (item['is_error'] as bool?) ?? false,
        );
      case 'image':
        return Message(
          uuid: uuid,
          role: role,
          kind: MessageKind.attachment,
          timestamp: timestamp,
          attachmentFilename: item['filename'] as String?,
          attachmentLocalPath: item['path'] as String?,
          attachmentRemoteUrl: item['url'] as String?,
        );
      default:
        return Message(
          uuid: uuid,
          role: role,
          kind: MessageKind.raw,
          timestamp: timestamp,
          rawLine: item.toString(),
        );
    }
  }

  static MessageRole _parseRole(String? r) {
    switch (r) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.unknown;
    }
  }

  static ToolUseStatus _parseToolStatus(String? s) {
    switch (s) {
      case 'approved':
        return ToolUseStatus.approved;
      case 'rejected':
        return ToolUseStatus.rejected;
      case 'executed':
        return ToolUseStatus.executed;
      default:
        return ToolUseStatus.pending;
    }
  }

  static DateTime _parseTs(dynamic v) {
    if (v is String) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt;
    }
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    }
    return DateTime.now();
  }

  static String _fallbackUuid(Map<String, dynamic> raw) {
    return 'raw-${raw.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
  }
}
