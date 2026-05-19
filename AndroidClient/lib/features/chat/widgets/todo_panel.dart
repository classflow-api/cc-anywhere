// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// todo_panel.dart
// 顶部固定折叠 panel,镜像 Mac TUI 的 "Update Todos" 体验。
// 监听 ChatRepository 的 TabChatState.todos,Tab 维度隔离。
// 详见需求规格 R-T1-001 ~ R-T1-011。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_repository.dart';
import '../../../models/todo_item.dart';
import '../../../theme/color_tokens.dart';

class TodoPanel extends ConsumerStatefulWidget {
  final String tabId;
  const TodoPanel({super.key, required this.tabId});

  @override
  ConsumerState<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends ConsumerState<TodoPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chatAsync = ref.watch(tabChatStateProvider(widget.tabId));
    final todos = chatAsync.valueOrNull?.todos ?? const <TodoItem>[];

    // R-T1-008:空 todos 隐藏整个 widget,不占空间
    if (todos.isEmpty) return const SizedBox.shrink();

    final completed = todos.where((e) => e.status == TodoStatus.completed).length;
    final total = todos.length;
    final inProgress = todos.firstWhere(
      (e) => e.status == TodoStatus.inProgress,
      orElse: () => const TodoItem(content: '', status: TodoStatus.pending),
    );
    final hasInProgress = inProgress.content.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.line, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(t, completed, total, hasInProgress ? inProgress.content : null),
          // R-T1-010:200ms 折叠/展开动画
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 1, color: t.line),
                        const SizedBox(height: 6),
                        ...todos.map((todo) => _buildRow(t, todo)),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// R-T1-003:折叠态 "📋 任务进度 N/M · 当前: XXX",无 in_progress 时显示已完成 / 待开始
  Widget _buildHeader(
    ColorTokens t,
    int completed,
    int total,
    String? currentInProgress,
  ) {
    final String trailing;
    if (currentInProgress != null) {
      // R-T1-009:超 30 字符截断。第二轮 review 🟡-1:用 Characters.take
      // 按 grapheme cluster 切,避免 String.substring 把 emoji / 非 BMP 字符
      // 的 UTF-16 surrogate pair 切坏成孤儿码点。
      final chars = currentInProgress.characters;
      final summary = chars.length > 30
          ? '${chars.take(30).toString()}…'
          : currentInProgress;
      trailing = '当前: $summary';
    } else if (completed == total) {
      trailing = '已完成 ✅';
    } else {
      trailing = '待开始';
    }

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.checklist_rounded, size: 16, color: t.accent),
            const SizedBox(width: 8),
            Text(
              '任务进度 $completed/$total',
              style: TextStyle(
                color: t.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '· $trailing',
                style: TextStyle(color: t.textMuted, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: t.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  /// R-T1-004:每项 icon + 文本。三态颜色 + 已完成 strikethrough。
  Widget _buildRow(ColorTokens t, TodoItem todo) {
    final (icon, color) = switch (todo.status) {
      TodoStatus.pending => (Icons.radio_button_unchecked, t.textMuted),
      TodoStatus.inProgress => (Icons.timelapse, t.accent),
      TodoStatus.completed => (Icons.check_circle, t.success),
    };
    final isDone = todo.status == TodoStatus.completed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              todo.content,
              style: TextStyle(
                color: isDone ? t.textMuted : t.text,
                fontSize: 12.5,
                height: 1.35,
                decoration: isDone ? TextDecoration.lineThrough : null,
                decorationColor: t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
