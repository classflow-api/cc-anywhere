/// Tab/会话模型 — 与 Mac 端 `tabs.json` 对齐
enum ClaudeStatus { running, idle, error, unknown }

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
