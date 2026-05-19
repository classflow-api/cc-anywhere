/// Tab/会话模型 — 与 Mac 端 `tabs.json` 对齐
enum ClaudeStatus { running, idle, error, unknown }

/// Claude 在该 Tab 内的活动状态（独立于 PTY 进程状态）。
/// working = Claude 在思考/调工具；waiting = Claude 等待用户输入。
enum ClaudeActivity { working, waiting }

ClaudeActivity parseClaudeActivity(String? s) {
  switch (s) {
    case 'working':
      return ClaudeActivity.working;
    default:
      return ClaudeActivity.waiting;
  }
}

ClaudeStatus parseClaudeStatus(String? s) {
  switch (s) {
    case 'running':
      return ClaudeStatus.running;
    case 'idle':
      return ClaudeStatus.idle;
    case 'error':
      return ClaudeStatus.error;
    default:
      return ClaudeStatus.unknown;
  }
}

class TabInfo {
  final String id;
  final String name;
  final String folder;
  final ClaudeStatus claudeStatus;
  /// Claude 活动状态（working / waiting）。默认 waiting。
  /// 由 Mac 端 hook 桥接驱动，通过 `tab.activity` 协议消息推送变化。
  final ClaudeActivity activity;
  final DateTime? lastActivityAt;
  final int unreadCount;
  final bool pendingToolUse;
  final String? lastPreview;
  final bool errorState;

  const TabInfo({
    required this.id,
    required this.name,
    required this.folder,
    required this.claudeStatus,
    this.activity = ClaudeActivity.waiting,
    this.lastActivityAt,
    this.unreadCount = 0,
    this.pendingToolUse = false,
    this.lastPreview,
    this.errorState = false,
  });

  TabInfo copyWith({
    String? id,
    String? name,
    String? folder,
    ClaudeStatus? claudeStatus,
    ClaudeActivity? activity,
    DateTime? lastActivityAt,
    int? unreadCount,
    bool? pendingToolUse,
    String? lastPreview,
    bool? errorState,
  }) =>
      TabInfo(
        id: id ?? this.id,
        name: name ?? this.name,
        folder: folder ?? this.folder,
        claudeStatus: claudeStatus ?? this.claudeStatus,
        activity: activity ?? this.activity,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        unreadCount: unreadCount ?? this.unreadCount,
        pendingToolUse: pendingToolUse ?? this.pendingToolUse,
        lastPreview: lastPreview ?? this.lastPreview,
        errorState: errorState ?? this.errorState,
      );

  factory TabInfo.fromJson(Map<String, dynamic> j) => TabInfo(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '(unnamed)',
        folder: (j['folder'] as String?) ?? '',
        claudeStatus: parseClaudeStatus(j['claude_status'] as String?),
        lastActivityAt: j['last_activity_at'] != null
            ? DateTime.tryParse(j['last_activity_at'] as String)
            : null,
        unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
        pendingToolUse: (j['pending_tool_use'] as bool?) ?? false,
        lastPreview: j['last_preview'] as String?,
        errorState: (j['error_state'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'folder': folder,
        'claude_status': claudeStatus.name,
        'last_activity_at': lastActivityAt?.toIso8601String(),
        'unread_count': unreadCount,
        'pending_tool_use': pendingToolUse,
        'last_preview': lastPreview,
        'error_state': errorState,
      };
}
