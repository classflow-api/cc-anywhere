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
  static const tabActivity = 'tab.activity';

  // 消息
  static const msgStream = 'msg.stream';
  static const msgHistoryRequest = 'msg.history.request';
  static const msgHistoryResponse = 'msg.history.response';
  static const msgRaw = 'msg.raw';

  // 输入
  static const inputText = 'input.text';
  static const inputImage = 'input.image';
  static const imageFetched = 'image.fetched';
  static const inputError = 'input.error';
  static const imageUploadBegin = 'image.upload.begin';
  static const imageUploadUrl = 'image.upload.url';
  static const imageUploadExpired = 'image.upload.expired';
  static const imageDownloadRequest = 'image.download.url';
  static const imageDownloadResponse = 'image.download.url.response';
  // (no-op placeholder so #36 deps are independent of protocol changes)
  static const slashListRequest = 'slash.list.request';
  static const slashListResponse = 'slash.list.response';
  static const toolUseApprove = 'tool_use.approve';

  // presence
  static const presenceMacOnline = 'presence.mac_online';
  static const presenceMacOffline = 'presence.mac_offline';
  static const presencePhoneCount = 'presence.phone_count';

  // 4.7 Hook 实时桥接（AskUserQuestion 远程交互）
  static const askQuestionPending = 'ask.question.pending';
  static const askQuestionAnswer = 'ask.question.answer';
  static const askQuestionAnswered = 'ask.question.answered';
  static const askQuestionTimeout = 'ask.question.timeout';
  /// F4 危险工具远程批准回执：phone → server → mac
  static const askToolApprovalAnswer = 'ask.tool_approval.answer';
  static const toolProgressPre = 'tool.progress.pre';
  static const toolProgressPost = 'tool.progress.post';
  static const notification = 'notification';
}

/// `notification` payload —— Mac App 桥接 Claude Notification hook,
/// Server 广播给所有 phone（mac → server → phone）。
///
/// 字段命名严格对齐 Server `protocol.Notification` (snake_case JSON tag)。
/// 协议见需求规格说明书 §3.2.7、§3.4.4，业务规则 R-F3-001 ~ R-F3-003。
class NotificationPayload {
  /// tab UUID（用于解析展示 [Tab xxx] 前缀）
  final String tabId;

  /// 枚举：`idle` / `permission_prompt` / `error`
  /// 决定 toast 颜色（R-F3-003：灰 / 黄 / 红）。
  final String notificationType;

  /// 通知标题（如 "Claude idle"）
  final String title;

  /// 通知正文
  final String message;

  const NotificationPayload({
    required this.tabId,
    required this.notificationType,
    required this.title,
    required this.message,
  });

  static NotificationPayload? tryFrom(Map<String, dynamic> data) {
    final tabId = data['tab_id'];
    final type = data['notification_type'];
    if (tabId is! String || type is! String) return null;
    final title = data['title'];
    final message = data['message'];
    return NotificationPayload(
      tabId: tabId,
      notificationType: type,
      title: title is String ? title : '',
      message: message is String ? message : '',
    );
  }
}

/// `ask.question.pending` payload —— Mac App 发起、Server 广播给所有 phone。
///
/// 字段命名严格对齐 Server `protocol.AskQuestionPending` (snake_case JSON tag)。
/// 需求规格说明书 §3.2.1 / R-F1-012：`allow_other` 字段缺失时默认为 true，
/// phone 端必须始终展示"自定义回答"输入项。
class AskQuestionPendingPayload {
  final String requestId;
  final String tabId;
  final String toolUseId;
  /// "user_question" | "tool_approval"
  final String askKind;
  final bool allowOther;
  /// 形如 `[{ question, header, multiSelect, options: [{ label, description }] }, ...]`
  /// 与 message.dart 的 AskUserQuestion 事后模式 questions 字段同结构。
  final List<Map<String, dynamic>> questions;
  final String? toolName;
  final Map<String, dynamic>? toolInput;
  // ⊕ R-F5: 子 agent 上下文（旧版 mac 端不发，全部 null → UI 降级）
  final String? parentToolUseId;
  final String? subAgentSummary;
  final bool isFromSubAgent;

  const AskQuestionPendingPayload({
    required this.requestId,
    required this.tabId,
    required this.toolUseId,
    required this.askKind,
    required this.allowOther,
    required this.questions,
    this.toolName,
    this.toolInput,
    this.parentToolUseId,
    this.subAgentSummary,
    this.isFromSubAgent = false,
  });

  static AskQuestionPendingPayload? tryFrom(Map<String, dynamic> data) {
    final requestId = data['request_id'];
    if (requestId is! String || requestId.isEmpty) return null;
    final tabId = data['tab_id'] as String? ?? '';
    final toolUseId = data['tool_use_id'] as String? ?? '';
    final askKind = data['ask_kind'] as String? ?? 'user_question';
    // R-F1-012:字段缺失则默认 true(始终展示自定义回答输入项)
    final allowOther = data['allow_other'] as bool? ?? true;
    final rawQs = data['questions'];
    final qs = <Map<String, dynamic>>[];
    if (rawQs is List) {
      for (final q in rawQs) {
        if (q is Map) qs.add(q.cast<String, dynamic>());
      }
    }
    final toolInput = data['tool_input'];
    return AskQuestionPendingPayload(
      requestId: requestId,
      tabId: tabId,
      toolUseId: toolUseId,
      askKind: askKind,
      allowOther: allowOther,
      questions: qs,
      toolName: data['tool_name'] as String?,
      toolInput: toolInput is Map
          ? toolInput.cast<String, dynamic>()
          : null,
      parentToolUseId: data['parent_tool_use_id'] as String?,
      subAgentSummary: data['sub_agent_summary'] as String?,
      isFromSubAgent: (data['is_from_sub_agent'] as bool?) ?? false,
    );
  }
}

/// `ask.question.answer` payload —— phone 提交给 Mac App。
///
/// answers 字段:key 是 question 原文,value 是用户选择的 label
/// 字符串或自定义回答(Other)的任意字符串。R-F1-014 不区分类型。
class AskQuestionAnswerPayload {
  final String requestId;
  final Map<String, String> answers;

  const AskQuestionAnswerPayload({
    required this.requestId,
    required this.answers,
  });

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'answers': answers,
      };
}

/// `ask.tool_approval.answer` payload —— phone 提交给 Mac App（F4 危险工具远程批准）。
///
/// 字段命名严格对齐 Server `protocol.AskToolApprovalAnswer` 与 Mac
/// `AskToolApprovalAnswerPayload`（snake_case）。Mac 端
/// `DependencyContainer.handleAskToolApprovalInbound` 解析后会调
/// `HookIpcServer.receiveApprovalFromWs(requestId, decision, reason)`。
///
/// decision 必填 "allow" | "deny"；reason 可选，仅在 deny 时填用户附加原因
/// （R-F4-005）。本类只承担"出站序列化"，不参与入站反序列化。
class AskToolApprovalAnswerPayload {
  final String requestId;
  /// "allow" | "deny"
  final String decision;
  /// 可选用户附加原因，仅 deny 路径有意义；空串/null 都不写入 JSON。
  final String? reason;

  const AskToolApprovalAnswerPayload({
    required this.requestId,
    required this.decision,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'decision': decision,
        if (reason != null && reason!.isNotEmpty) 'reason': reason,
      };
}

/// `tab.activity` payload —— Mac → server → phone，按 tab 推送 Claude 活动状态。
/// 由 Mac 端 hook 桥接驱动（PreToolUse → working / Notification idle → waiting），
/// 只在状态真发生变化时推送（增量）。
class TabActivityPayload {
  final String tabId;
  /// "working" | "waiting"
  final String activity;

  const TabActivityPayload({required this.tabId, required this.activity});

  static TabActivityPayload? tryFrom(Map<String, dynamic> data) {
    final tabId = data['tab_id'];
    if (tabId is! String || tabId.isEmpty) return null;
    final activity = (data['activity'] as String?) ?? 'waiting';
    return TabActivityPayload(tabId: tabId, activity: activity);
  }
}

/// `ask.question.answered` payload —— Mac App winner 仲裁后广播给所有 phone。
class AskQuestionAnsweredPayload {
  final String requestId;
  final String answeredBy;
  final Map<String, String> answers;

  const AskQuestionAnsweredPayload({
    required this.requestId,
    required this.answeredBy,
    required this.answers,
  });

  static AskQuestionAnsweredPayload? tryFrom(Map<String, dynamic> data) {
    final requestId = data['request_id'];
    if (requestId is! String || requestId.isEmpty) return null;
    final answeredBy = data['answered_by'] as String? ?? '';
    final rawAnswers = data['answers'];
    final answers = <String, String>{};
    if (rawAnswers is Map) {
      rawAnswers.forEach((k, v) {
        if (k is String && v is String) answers[k] = v;
      });
    }
    return AskQuestionAnsweredPayload(
      requestId: requestId,
      answeredBy: answeredBy,
      answers: answers,
    );
  }
}

/// `ask.question.timeout` payload —— Mac App 在 5 分钟内无人回答时广播,
/// 所有 phone 撤销卡片。
class AskQuestionTimeoutPayload {
  final String requestId;
  /// "timeout" | "cancelled"
  final String reason;

  const AskQuestionTimeoutPayload({
    required this.requestId,
    required this.reason,
  });

  static AskQuestionTimeoutPayload? tryFrom(Map<String, dynamic> data) {
    final requestId = data['request_id'];
    if (requestId is! String || requestId.isEmpty) return null;
    return AskQuestionTimeoutPayload(
      requestId: requestId,
      reason: data['reason'] as String? ?? 'timeout',
    );
  }
}

/// `tool.progress.pre` payload —— Mac App 在 PreToolUse hook 命中时广播给所有 phone。
///
/// 协议见需求规格说明书 §3.2.5，业务规则 R-F2-001 ~ R-F2-005。
/// `tool_input` 中的长字段（command / file_path / content）由 Mac 端截断至 200 字符
/// （R-F2-004），phone 端再按 tool_name 提取摘要并二次截断 60 字符展示。
class ToolProgressPrePayload {
  final String tabId;
  final String toolUseId;
  final String toolName;
  /// 原始 tool_input（已由 Mac 端截断长字段至 200 字符）。
  final Map<String, dynamic> toolInput;

  const ToolProgressPrePayload({
    required this.tabId,
    required this.toolUseId,
    required this.toolName,
    required this.toolInput,
  });

  static ToolProgressPrePayload? tryFrom(Map<String, dynamic> data) {
    final toolUseId = data['tool_use_id'];
    if (toolUseId is! String || toolUseId.isEmpty) return null;
    final toolName = data['tool_name'];
    if (toolName is! String || toolName.isEmpty) return null;
    final input = data['tool_input'];
    return ToolProgressPrePayload(
      tabId: data['tab_id'] as String? ?? '',
      toolUseId: toolUseId,
      toolName: toolName,
      toolInput: input is Map ? input.cast<String, dynamic>() : <String, dynamic>{},
    );
  }
}

/// `tool.progress.post` payload —— Mac App 在 PostToolUse hook 命中时广播。
///
/// 协议见需求规格说明书 §3.2.6。`success=true` → phone 端移除进度条；
/// `success=false` → 变红色 toast 显示 5 秒后消失（场景 F2-S3、§3.4.3）。
class ToolProgressPostPayload {
  final String tabId;
  final String toolUseId;
  final String toolName;
  final bool success;
  /// 失败时的错误描述；成功时为 null 或空串。
  final String? error;

  const ToolProgressPostPayload({
    required this.tabId,
    required this.toolUseId,
    required this.toolName,
    required this.success,
    this.error,
  });

  static ToolProgressPostPayload? tryFrom(Map<String, dynamic> data) {
    final toolUseId = data['tool_use_id'];
    if (toolUseId is! String || toolUseId.isEmpty) return null;
    final toolName = data['tool_name'] as String? ?? '';
    final success = data['success'] as bool? ?? true;
    final rawErr = data['error'];
    final err = rawErr is String && rawErr.isNotEmpty ? rawErr : null;
    return ToolProgressPostPayload(
      tabId: data['tab_id'] as String? ?? '',
      toolUseId: toolUseId,
      toolName: toolName,
      success: success,
      error: err,
    );
  }
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
