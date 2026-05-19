// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// todo_item.dart
// Claude Code TodoWrite 工具维护的单条任务项。三态：pending / in_progress / completed。
// 详见需求规格 R-T1-001 ~ R-T1-011。

enum TodoStatus {
  pending,
  inProgress,
  completed;

  /// 从 JSONL record 字符串解析。未知值返回 null（safe degradation）。
  static TodoStatus? tryParse(String? s) {
    switch (s) {
      case 'pending':
        return TodoStatus.pending;
      case 'in_progress':
        return TodoStatus.inProgress;
      case 'completed':
        return TodoStatus.completed;
      default:
        return null;
    }
  }
}

class TodoItem {
  final String content;
  final TodoStatus status;

  const TodoItem({
    required this.content,
    required this.status,
  });

  /// 从 TodoWrite tool_use input.todos 单项解析。
  /// 字段缺失 / 类型错误 / 未知 status → 返回 null（safe degradation，
  /// 防止 Claude Code 升级字段名后整个 panel 崩溃）。
  /// 注：Claude Code 当前 TodoWrite schema 仅 content / status / activeForm；
  /// 不解析 activeForm（与 content 重复度高，UI 用 content 就够）。
  static TodoItem? tryFrom(Map<String, dynamic> json) {
    final content = json['content'];
    if (content is! String || content.isEmpty) return null;
    final status = TodoStatus.tryParse(json['status'] as String?);
    if (status == null) return null;
    return TodoItem(content: content, status: status);
  }

  /// 解析 TodoWrite tool_use input.todos 整个数组。
  static List<TodoItem> parseList(dynamic todosField) {
    if (todosField is! List) return const [];
    final result = <TodoItem>[];
    for (final item in todosField) {
      if (item is Map) {
        final parsed = TodoItem.tryFrom(item.cast<String, dynamic>());
        if (parsed != null) result.add(parsed);
      }
    }
    return result;
  }
}
