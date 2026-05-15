/// Phone 端工具进度指示器
///
/// 监听 `tool.progress.pre` / `tool.progress.post` 协议消息，
/// 在消息列表底部按 tool_use_id 维护一行可见的执行状态：
///
/// - `pre` 到达：插入"⚡ 正在执行 [tool_name] [摘要]"灰色进度条
/// - `post.success=true`：立即移除该 tool_use_id 对应的进度条
/// - `post.success=false`：变红色 toast 5 秒后自动消失
///
/// 设计依据：
/// - 需求规格说明书 §3.1 F2（操作场景 + R-F2-001 ~ R-F2-005）
/// - 需求规格说明书 §3.4.3 ToolProgressIndicator
/// - 技术实施文档 §4.7.2
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ws_client.dart';
import '../models/protocol_message.dart';
import '../theme/color_tokens.dart';

// ---------------------------------------------------------------------------
// 数据模型
// ---------------------------------------------------------------------------

/// 单个进行中（或刚失败正在淡出）的工具调用项。
class ToolProgressItem {
  final String toolUseId;
  final String tabId;
  final String toolName;
  /// tool_input 截断后的摘要（≤ 60 字符）。
  final String summary;
  final DateTime startAt;
  /// null = 运行中；true = 成功（实际上 success 会被立即移除，
  /// 此字段主要为 false 时承载失败态以触发红色 toast 渲染）。
  final bool? success;
  final String? error;

  const ToolProgressItem({
    required this.toolUseId,
    required this.tabId,
    required this.toolName,
    required this.summary,
    required this.startAt,
    this.success,
    this.error,
  });

  ToolProgressItem copyWith({
    bool? success,
    String? error,
  }) =>
      ToolProgressItem(
        toolUseId: toolUseId,
        tabId: tabId,
        toolName: toolName,
        summary: summary,
        startAt: startAt,
        success: success ?? this.success,
        error: error ?? this.error,
      );
}

// ---------------------------------------------------------------------------
// 摘要规则（按 tool_name 提取关键字段并截断 60 字符）
// ---------------------------------------------------------------------------

/// 全局摘要长度（字符数）。Mac 端已先截断 200 字符（R-F2-004），
/// phone 端再二次截断到 60 字符以在一行内显示。
const int _kSummaryMaxLen = 60;

/// 根据 tool_name 提取可读摘要：
/// - `Bash`：command 字段
/// - `Read` / `Write` / `Edit`：file_path 的 basename
/// - 其他：整个 input 做 JSON encode
/// 所有结果统一截断 60 字符（超长尾巴用 `…`）。
String summarizeToolInput(String toolName, Map<String, dynamic> input) {
  String raw;
  switch (toolName) {
    case 'Bash':
      raw = (input['command'] as String?) ?? '';
      break;
    case 'Read':
    case 'Write':
    case 'Edit':
      final fp = (input['file_path'] as String?) ?? '';
      raw = _basename(fp);
      break;
    default:
      try {
        raw = jsonEncode(input);
      } catch (_) {
        raw = input.toString();
      }
  }
  return _truncate(raw, _kSummaryMaxLen);
}

String _basename(String path) {
  if (path.isEmpty) return '';
  // 同时兼容 posix 与 windows 风格，取最后一段。
  final idx = path.lastIndexOf(RegExp(r'[/\\]'));
  return idx < 0 ? path : path.substring(idx + 1);
}

String _truncate(String s, int max) {
  if (s.length <= max) return s;
  return '${s.substring(0, max)}…';
}

// ---------------------------------------------------------------------------
// 状态管理（Riverpod StateNotifier — 与项目既有 ThemeModeNotifier 一致）
// ---------------------------------------------------------------------------

/// 失败态自动淡出的时长（§3.4.3：变红色 toast 5 秒后消失）。
const Duration _kFailureLinger = Duration(seconds: 5);

class ToolProgressNotifier extends StateNotifier<List<ToolProgressItem>> {
  ToolProgressNotifier() : super(const <ToolProgressItem>[]);

  /// 失败项的延迟移除 timer，按 tool_use_id 索引。dispose 时统一取消。
  final Map<String, Timer> _failureTimers = {};

  /// 收到 `tool.progress.pre`：追加一项运行中。
  /// 如果同一 tool_use_id 已存在（极端重复或重连重放），保持最早的那条不变。
  void onPre(ToolProgressPrePayload payload) {
    if (state.any((e) => e.toolUseId == payload.toolUseId)) return;
    final item = ToolProgressItem(
      toolUseId: payload.toolUseId,
      tabId: payload.tabId,
      toolName: payload.toolName,
      summary: summarizeToolInput(payload.toolName, payload.toolInput),
      startAt: DateTime.now(),
    );
    state = [...state, item];
  }

  /// 收到 `tool.progress.post`：
  /// - success：立即移除
  /// - failure：原项标记为失败 + 5 秒后自动移除
  void onPost(ToolProgressPostPayload payload) {
    final idx = state.indexWhere((e) => e.toolUseId == payload.toolUseId);
    if (idx < 0) {
      // 没有匹配的 pre（可能是 Read 这类未发 pre 的工具），失败时仍可
      // 直接造一条临时项用于显示 toast。
      if (!payload.success) {
        final tmp = ToolProgressItem(
          toolUseId: payload.toolUseId,
          tabId: payload.tabId,
          toolName: payload.toolName,
          summary: '',
          startAt: DateTime.now(),
          success: false,
          error: payload.error,
        );
        state = [...state, tmp];
        _scheduleRemoval(payload.toolUseId);
      }
      return;
    }
    if (payload.success) {
      _removeById(payload.toolUseId);
      return;
    }
    // 失败：保留并标记，5 秒后移除
    final updated = state[idx].copyWith(success: false, error: payload.error);
    final next = [...state];
    next[idx] = updated;
    state = next;
    _scheduleRemoval(payload.toolUseId);
  }

  void _scheduleRemoval(String toolUseId) {
    _failureTimers[toolUseId]?.cancel();
    _failureTimers[toolUseId] = Timer(_kFailureLinger, () {
      _failureTimers.remove(toolUseId);
      _removeById(toolUseId);
    });
  }

  void _removeById(String toolUseId) {
    if (!state.any((e) => e.toolUseId == toolUseId)) return;
    state = state.where((e) => e.toolUseId != toolUseId).toList();
  }

  /// 切 tab / 断线时可清空（当前未自动触发；保留给上层按需调用）。
  void clear() {
    for (final t in _failureTimers.values) {
      t.cancel();
    }
    _failureTimers.clear();
    state = const [];
  }

  @override
  void dispose() {
    for (final t in _failureTimers.values) {
      t.cancel();
    }
    _failureTimers.clear();
    super.dispose();
  }
}

/// 全局 ToolProgress 状态。
///
/// 内部订阅 [wsClientProvider].inbound，按消息 type 自路由到 onPre / onPost。
/// 这样上层只需 `ref.watch(toolProgressProvider)` 即可拿到当前可见项列表。
final toolProgressProvider =
    StateNotifierProvider<ToolProgressNotifier, List<ToolProgressItem>>(
  (ref) {
    final notifier = ToolProgressNotifier();
    final ws = ref.watch(wsClientProvider);
    final sub = ws.inbound.listen((msg) {
      switch (msg.type) {
        case ProtocolType.toolProgressPre:
          final p = ToolProgressPrePayload.tryFrom(msg.data);
          if (p != null) notifier.onPre(p);
          break;
        case ProtocolType.toolProgressPost:
          final p = ToolProgressPostPayload.tryFrom(msg.data);
          if (p != null) notifier.onPost(p);
          break;
      }
    });
    ref.onDispose(() {
      sub.cancel();
      notifier.dispose();
    });
    return notifier;
  },
);

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------

/// 消息列表底部的工具进度指示器。
///
/// 当 [tabId] 不为 null 时仅展示该 tab 的项；为 null 时展示全部
/// （当前 phone 端单 tab 一次只查看一条，所以一般传具体 tabId）。
class ToolProgressIndicator extends ConsumerWidget {
  final String? tabId;
  const ToolProgressIndicator({super.key, this.tabId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(toolProgressProvider);
    final items = tabId == null
        ? all
        : all.where((e) => e.tabId == tabId).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _ToolProgressRow(item: it),
            ),
        ],
      ),
    );
  }
}

class _ToolProgressRow extends StatelessWidget {
  final ToolProgressItem item;
  const _ToolProgressRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final failed = item.success == false;
    final bg = failed ? t.danger.withValues(alpha: 0.14) : t.bgInset;
    final border = failed ? t.danger.withValues(alpha: 0.6) : t.line;
    final fg = failed ? t.danger : t.textMuted;
    final iconColor = failed ? t.danger : t.accent;

    final summary = item.summary;
    final mainText = failed
        ? (item.error?.isNotEmpty == true
            ? '${item.toolName} 失败：${item.error}'
            : '${item.toolName} 执行失败')
        : (summary.isEmpty
            ? '正在执行 ${item.toolName}'
            : '正在执行 ${item.toolName}：$summary');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.bolt_rounded,
            size: 14,
            color: iconColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              mainText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: failed ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
