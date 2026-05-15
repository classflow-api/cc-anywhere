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
  askUserQuestion,
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

  /// AskUserQuestion 工具调用专用:Anthropic schema 的 questions 数组,
  /// 每项 { question, header, multiSelect, options: [{ label, description, preview? }] }
  final List<Map<String, dynamic>>? questions;

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
    this.questions,
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
  /// 支持的结构：
  /// 0. Claude Code 真实结构(嵌套):{type:"user"|"assistant", uuid, message:{role, content:[...]}, ...}
  /// 1. {uuid, role, type:"text", text, timestamp}
  /// 2. {uuid, role, content:[{type, ...}], timestamp}
  /// 跳过的顶层类型:attachment / system / summary / file-history-snapshot 等元数据
  /// 解析失败返回 raw kind
  static List<Message> fromRaw(Map<String, dynamic> raw) {
    try {
      final uuid = (raw['uuid'] as String?) ?? (raw['id'] as String?);
      final ts = _parseTs(raw['timestamp'] ?? raw['created_at']);

      // 形式 0:Claude Code 真实 JSONL — 顶层 type 是 user/assistant,内容嵌在 message.content 里。
      // 顶层非业务类型(attachment / system / summary / file-history-snapshot / bridge-session 等)
      // 直接跳过,不向用户展示原始 JSON。
      final topType = raw['type'] as String?;
      if (topType == 'user' || topType == 'assistant') {
        // isMeta=true 的 user 消息是 Claude Code 系统注入的内部指令
        // (例如 "Continue from where you left off."、"/remote-control" 命令等),
        // 用户没有真的发这些,过滤掉。
        if (topType == 'user' && raw['isMeta'] == true) {
          return const [];
        }
        final inner = raw['message'];
        if (inner is Map<String, dynamic>) {
          final innerRole = _parseRole((inner['role'] as String?) ?? topType);
          final innerContent = inner['content'];
          if (innerContent is List && innerContent.isNotEmpty) {
            final out = <Message>[];
            for (var i = 0; i < innerContent.length; i++) {
              final item = innerContent[i];
              if (item is! Map<String, dynamic>) continue;
              out.add(_parseSingle(
                uuid: '${uuid ?? _fallbackUuid(raw)}#$i',
                role: innerRole,
                timestamp: ts,
                item: item,
              ));
            }
            // assistant 仅含 "No response requested." 单条文本时,
            // 是 Claude 对 isMeta user 的固定占位回复,无业务价值,过滤掉。
            if (topType == 'assistant' &&
                out.length == 1 &&
                out.first.kind == MessageKind.text &&
                (out.first.text?.trim() == 'No response requested.')) {
              return const [];
            }
            // user 发图通过 `@<cc-anywhere-inbox-path>` 文本注入 Claude TUI,
            // JSONL 里这条 user message 只是路径文本。把它识别为 attachment 卡片,
            // 由 ChatRepository 后续通过 image.download.url 协议补 remoteUrl 显示缩略图。
            if (topType == 'user') {
              _rewriteInboxRefAsAttachment(out);
            }
            if (out.isNotEmpty) return out;
          }
          // user/assistant 但 content 是字符串
          if (innerContent is String && innerContent.isNotEmpty) {
            // Claude Code 把若干 IDE/CLI 层事件序列化为 XML 内部 transcript 嵌进 user message,
            // 这些是 Claude 给自己看的系统层 representation,用户不需要看到 XML,精准匹配跳过。
            const internalTags = [
              '<command-name>',         // slash command 调用(如 /clear/help/compact)
              '<local-command-stdout>', // 本地 ! 命令的 stdout
              '<local-command-stderr>', // 本地 ! 命令的 stderr
              '<task-notification>',    // 后台 task 状态变化通知
              '<bash-input>',           // Bash 工具的执行输入
              '<bash-stdout>',          // Bash 工具的 stdout
              '<bash-stderr>',          // Bash 工具的 stderr
              '<system-reminder>',      // 系统提醒(钩子注入)
            ];
            final trimmedContent = innerContent.trimLeft();
            if (topType == 'user' &&
                internalTags.any(trimmedContent.startsWith)) {
              return const [];
            }
            final stringMsg = [
              Message(
                uuid: uuid ?? _fallbackUuid(raw),
                role: innerRole,
                kind: MessageKind.text,
                timestamp: ts,
                text: innerContent,
              ),
            ];
            // 同 list 分支:把 inbox path 改写成 attachment 卡片,避免双卡片。
            if (topType == 'user') {
              _rewriteInboxRefAsAttachment(stringMsg);
            }
            return stringMsg;
          }
        }
        // 没匹配上但顶层声明是 user/assistant — 静默丢弃,避免渲染"无法解析"卡片
        return const [];
      }
      // 顶层是 Claude Code 内部元数据,丢弃 — 不向用户展示原始 JSON。
      // 注:topType 命中 user/assistant 已在前面 return,这里只剩元数据类型。
      const metaTypes = {
        'attachment',
        'system',
        'summary',
        'file-history-snapshot',
        'bridge-session',
        'permission-mode',
        'last-prompt',
      };
      if (topType != null && metaTypes.contains(topType)) {
        return const [];
      }
      // 兜底:任何含有 sessionId 但无 message 字段的行,基本是元数据,跳过避免渲染 raw。
      if (topType != null && raw['message'] == null && raw['sessionId'] != null) {
        return const [];
      }

      final role = _parseRole(raw['role'] as String?);

      // 形式 1:扁平 {type, text, ...}
      if (raw['content'] is! List && raw['type'] != null) {
        final m = _parseSingle(
          uuid: uuid ?? _fallbackUuid(raw),
          role: role,
          timestamp: ts,
          item: raw,
        );
        return [m];
      }

      // 形式 2:顶层 content 数组
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
        final toolName = item['name'] as String?;
        final input = (item['input'] as Map?)?.cast<String, dynamic>();
        // 特殊化:AskUserQuestion 工具用专用卡片渲染(问题 + 选项交互)
        if (toolName == 'AskUserQuestion' && input != null) {
          final rawQs = input['questions'];
          if (rawQs is List) {
            final qs = rawQs
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList();
            return Message(
              uuid: uuid,
              role: role,
              kind: MessageKind.askUserQuestion,
              timestamp: timestamp,
              toolName: toolName,
              toolUseId: item['id'] as String?,
              toolStatus: _parseToolStatus(item['status'] as String?),
              questions: qs,
            );
          }
        }
        return Message(
          uuid: uuid,
          role: role,
          kind: MessageKind.toolUse,
          timestamp: timestamp,
          toolName: toolName,
          toolInput: input,
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

  /// 把 user 消息中"路径形式"的 text 卡片改写为 attachment 卡片(就地修改 list 元素)。
  ///
  /// 识别规则:整条 text 是 `@<path>` 形式 + path 中含 `cc-anywhere/inbox/`。
  /// 这种 text 实际是 Mac 端 InputInjector 把附件路径(图片或任意文件)
  /// 注入 Claude TUI 产生的 user echo,phone 端应渲染为 attachment 卡片。
  static void _rewriteInboxRefAsAttachment(List<Message> out) {
    // 任意后缀都接受 — 协议复用 image.* 通道,实际支持任意文件类型;
    // attachment_card 根据 filename 后缀决定渲染图片缩略图还是文件图标。
    // path 前半段允许空格(macOS Application Support 含空格),inbox/ 后 filename 不允许空格。
    final re = RegExp(
      r'^@(/.*?cc-anywhere/inbox/[^\s/]+)\s*$',
      caseSensitive: false,
    );
    for (var i = 0; i < out.length; i++) {
      final m = out[i];
      if (m.kind != MessageKind.text) continue;
      final t = m.text?.trim() ?? '';
      final match = re.firstMatch(t);
      if (match == null) continue;
      final fullPath = match.group(1)!;
      final filename = fullPath.split('/').last;
      out[i] = Message(
        uuid: m.uuid,
        role: m.role,
        kind: MessageKind.attachment,
        timestamp: m.timestamp,
        attachmentFilename: filename,
        // remoteUrl 由 ChatRepository 通过 image.download.url 协议异步补
        // path 用 Mac 端原始绝对路径(信息保留,但 phone 端不本地用)
        attachmentLocalPath: fullPath,
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
