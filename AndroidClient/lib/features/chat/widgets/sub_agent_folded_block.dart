// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// sub_agent_folded_block.dart
// 手机端子 agent 折叠块 widget。默认折叠，点开展示子 agent thinking /
// tool_use / tool_result 序列。详见需求规格说明书 R-F4-001 ~ R-F4-005。

import 'package:flutter/material.dart';

import '../../../theme/color_tokens.dart';

/// 子 agent 折叠块数据模型（L4 §3.4 业务规则 R-F4-001 ~ R-F4-005）。
///
/// 一个 SubAgentBlock 对应 mac 端一次 Task 工具调用产生的子 agent 全生命周期：
/// - parentToolUseId：父 session 中 Task tool_use 的 id（race 未匹配时可能 null，
///   仍按 agentId 聚合，UI 上只是无法链接到主流的"父 Task 卡片"，不影响展示）
/// - agentId：mac 端 JSONL 抽取的子 agent 短 hash（始终非 null）
/// - promptSummary：截断到 60 字符的 Task input.prompt（标题摘要）
/// - children：sidechain 消息的原始 JSONL record（按到达顺序，每条仍是 AnyJSON Map）
/// - finalResult：父 session 内 Task 工具的最终 tool_result（来自非 sidechain message
///   的内嵌 content；可能含 is_error → status=failed）
/// - status：'running' | 'done' | 'failed'
///
/// 设计 WHY：children 故意保留原 JSONL Map（而非 Message），让 widget 决定如何快速
/// 概览（content 类型 + 短摘要），避免重复走 Message 解析器、避免一份 sidechain 内容
/// 被同时解析进主流 messages 与折叠块导致双卡。
class SubAgentBlock {
  final String? parentToolUseId;
  final String agentId;
  final String promptSummary;
  final List<Map<String, dynamic>> children;
  Map<String, dynamic>? finalResult;
  String status;

  SubAgentBlock({
    required this.agentId,
    required this.promptSummary,
    this.parentToolUseId,
    List<Map<String, dynamic>>? children,
    this.finalResult,
    this.status = 'running',
  }) : children = children ?? [];

  /// R-F4-002：步数 = sidechain children 数 + (finalResult 到达则 +1)
  int get stepCount => children.length + (finalResult != null ? 1 : 0);
}

/// 子 agent 折叠块 widget（L4 §3.4）。
///
/// 默认折叠（R-F4-001）；失败时 initState 自动展开（R-F4-004）。
/// 左侧 2px 蓝色色条作为"子 agent 块"视觉标识（R-F4-005）。
class SubAgentFoldedBlock extends StatefulWidget {
  final SubAgentBlock block;

  const SubAgentFoldedBlock({super.key, required this.block});

  @override
  State<SubAgentFoldedBlock> createState() => _SubAgentFoldedBlockState();
}

class _SubAgentFoldedBlockState extends State<SubAgentFoldedBlock> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // R-F4-004：失败时自动展开，让用户看到错误细节，不再强制点击。
    if (widget.block.status == 'failed') _expanded = true;
  }

  @override
  void didUpdateWidget(covariant SubAgentFoldedBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // status 从 running/done 变为 failed 时也自动展开（R-F4-004 兜底：
    // 失败结果可能晚于 widget mount 才到达）。
    if (widget.block.status == 'failed' && oldWidget.block.status != 'failed') {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // R-F4-005：2px 蓝色左侧色条（与普通消息卡片视觉区分）
          Container(
            width: 2,
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            constraints: const BoxConstraints(minHeight: 32),
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: t.bgInset,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.line),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(t),
                      if (_expanded) ...[
                        const SizedBox(height: 10),
                        ..._buildChildrenList(t),
                        if (widget.block.finalResult != null) ...[
                          const SizedBox(height: 8),
                          _buildFinalResult(t),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorTokens t) {
    final b = widget.block;
    // R-F4-003：含 error 字段或 status=failed → ❌；finalResult 到达 → ✅；尚未到达 → 🔄
    final IconData statusIcon;
    final Color statusColor;
    final String statusLabel;
    switch (b.status) {
      case 'failed':
        statusIcon = Icons.error_outline_rounded;
        statusColor = t.danger;
        statusLabel = '失败';
        break;
      case 'done':
        statusIcon = Icons.check_circle_rounded;
        statusColor = t.success;
        statusLabel = '已完成';
        break;
      default:
        statusIcon = Icons.autorenew_rounded;
        statusColor = t.accent;
        statusLabel = '运行中';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⚡ icon — 标题栏一直可见，明确标识"子 agent 块"
        Icon(Icons.bolt_rounded, size: 16, color: t.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Task 子 agent',
                    style: TextStyle(
                      color: t.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (b.promptSummary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  b.promptSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(statusIcon, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    '$statusLabel · ${b.stepCount} 步',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Icon(
          _expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: t.textMuted,
        ),
      ],
    );
  }

  /// 展开后的 children 行：每条 sidechain JSONL record 一行简短摘要。
  ///
  /// WHY 不复用 Message + 子卡片：children 是"子 agent 内部轨迹"，性质上是
  /// 给用户"看一眼运行没跑偏"的快速预览，而非主对话流交互。重用 ToolUseCard
  /// 等会拉入完整交互（批准按钮等），既不需要又容易跟主流 dedup 冲突。
  List<Widget> _buildChildrenList(ColorTokens t) {
    return [
      for (final raw in widget.block.children)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _ChildLine(record: raw, palette: t),
        ),
    ];
  }

  Widget _buildFinalResult(ColorTokens t) {
    final result = widget.block.finalResult!;
    final preview = _extractFinalResultPreview(result);
    final isErr = widget.block.status == 'failed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.bgElev,
        border: Border.all(
          color: (isErr ? t.danger : t.success).withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isErr ? Icons.error_outline_rounded : Icons.flag_rounded,
            size: 14,
            color: isErr ? t.danger : t.success,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              preview,
              style: TextStyle(
                color: t.text,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 从 finalResult 的 message.content 中找出 tool_result 文本（截断 400 字）。
  /// 不展开为多行卡片，与 children 风格一致：折叠块只做"概览"，详情走主流。
  String _extractFinalResultPreview(Map<String, dynamic> record) {
    try {
      final inner = record['message'];
      if (inner is Map) {
        final content = inner['content'];
        if (content is List) {
          for (final item in content) {
            if (item is Map && item['type'] == 'tool_result') {
              final raw = item['content'];
              if (raw is String) return _clamp(raw, 400);
              if (raw is List && raw.isNotEmpty && raw.first is Map) {
                final t = (raw.first as Map)['text'];
                if (t is String) return _clamp(t, 400);
              }
            }
          }
        } else if (content is String) {
          return _clamp(content, 400);
        }
      }
    } catch (_) {/* 兜底走 raw 摘要 */}
    return '(已完成，无可预览内容)';
  }

  String _clamp(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';
}

/// 单条 children 行：根据 message.content 推断类型 → 摘要。
/// 不渲染富 UI，避免引入子 agent 卡片体系（与主流 Message 渲染分离）。
class _ChildLine extends StatelessWidget {
  final Map<String, dynamic> record;
  final ColorTokens palette;

  const _ChildLine({required this.record, required this.palette});

  @override
  Widget build(BuildContext context) {
    final summary = _summarize(record);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
            child: Icon(
              summary.icon,
              size: 12,
              color: palette.textFaint,
            ),
          ),
          Expanded(
            child: Text(
              summary.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String text}) _summarize(Map<String, dynamic> r) {
    try {
      final inner = r['message'];
      if (inner is Map) {
        final content = inner['content'];
        if (content is List && content.isNotEmpty) {
          for (final item in content) {
            if (item is! Map) continue;
            final type = item['type'];
            switch (type) {
              case 'thinking':
                final t = (item['thinking'] as String?) ?? '';
                return (
                  icon: Icons.auto_awesome_outlined,
                  text: 'thinking: ${_clamp(t, 200)}',
                );
              case 'text':
                final t = (item['text'] as String?) ?? '';
                return (
                  icon: Icons.chat_bubble_outline_rounded,
                  text: _clamp(t, 200),
                );
              case 'tool_use':
                final name = (item['name'] as String?) ?? '?';
                final input = item['input'];
                final hint = _toolUseHint(name, input);
                return (
                  icon: Icons.build_outlined,
                  text: 'tool_use: $name${hint.isEmpty ? '' : ' · $hint'}',
                );
              case 'tool_result':
                final raw = item['content'];
                String c = '';
                if (raw is String) {
                  c = raw;
                } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
                  c = ((raw.first as Map)['text'] as String?) ?? '';
                }
                return (
                  icon: Icons.read_more_rounded,
                  text: 'tool_result: ${_clamp(c, 200)}',
                );
            }
          }
        } else if (content is String) {
          return (
            icon: Icons.chat_bubble_outline_rounded,
            text: _clamp(content, 200),
          );
        }
      }
    } catch (_) {/* fallthrough */}
    // 兜底：直接 toString 防止"看不见任何东西"。子 agent 内部本身就是辅助预览。
    final fallback = r.toString();
    return (icon: Icons.notes_rounded, text: _clamp(fallback, 200));
  }

  String _toolUseHint(String name, dynamic input) {
    if (input is! Map) return '';
    switch (name) {
      case 'Bash':
        final cmd = input['command'];
        if (cmd is String) return _clamp(cmd, 80);
        return '';
      case 'Read':
      case 'Write':
      case 'Edit':
      case 'MultiEdit':
        final path = input['file_path'];
        if (path is String) return _clamp(path, 80);
        return '';
      default:
        return '';
    }
  }

  String _clamp(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';
}
