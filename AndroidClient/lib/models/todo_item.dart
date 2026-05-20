// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// todo_item.dart
// Claude Code 2.0+ 任务工具三件套(TaskCreate/TaskUpdate/TaskList)的数据模型。
//
// 历史说明: 旧版 Claude Code 用 TodoWrite(一次性覆盖整个 todos 列表),
// 2.0.77+ 改为 TaskCreate/TaskUpdate/TaskList 增量操作。本类名保留 "Todo"
// 仅为避免 import 路径破坏式重命名,实际承载 Task 数据。
//
// 四态: pending / in_progress / completed / deleted。详见 R-T1-001 ~ R-T1-011。

enum TodoStatus {
  pending,
  inProgress,
  completed,
  deleted;

  /// 从 TaskUpdate input.status 字符串解析。未知值返回 null(safe degradation)。
  static TodoStatus? tryParse(String? s) {
    switch (s) {
      case 'pending':
        return TodoStatus.pending;
      case 'in_progress':
        return TodoStatus.inProgress;
      case 'completed':
        return TodoStatus.completed;
      case 'deleted':
        return TodoStatus.deleted;
      default:
        return null;
    }
  }
}

class TodoItem {
  /// Claude Code 分配的短 id,从 TaskCreate 的 tool_result("Task #N created")
  /// 解析得到。TaskUpdate input.taskId 引用同一 id。
  final String taskId;
  final String subject;
  final TodoStatus status;
  final String? activeForm;

  const TodoItem({
    required this.taskId,
    required this.subject,
    required this.status,
    this.activeForm,
  });

  TodoItem copyWith({TodoStatus? status}) => TodoItem(
        taskId: taskId,
        subject: subject,
        status: status ?? this.status,
        activeForm: activeForm,
      );
}
