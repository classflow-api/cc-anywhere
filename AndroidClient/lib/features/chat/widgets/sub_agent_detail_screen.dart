// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// sub_agent_detail_screen.dart
// 点击底部 SubAgentRunnerBar 任一 sub-agent 进入此页,显示完整运行态:
// - 任务摘要(promptSummary)
// - 全部 children (thinking / tool_use / tool_result) 时间线
// - finalResult (如已到达)
// 状态实时刷新(监听 watchSubAgents stream)。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_repository.dart';
import '../../../theme/color_tokens.dart';
import 'sub_agent_folded_block.dart';

class SubAgentDetailScreen extends ConsumerWidget {
  final String tabId;
  final String agentId;
  const SubAgentDetailScreen({
    super.key,
    required this.tabId,
    required this.agentId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(StreamProvider.family<List<SubAgentBlock>, String>(
        (ref, id) => ref.watch(chatRepositoryProvider).watchSubAgents(id))(tabId));
    final blocks = async.valueOrNull ?? const <SubAgentBlock>[];
    SubAgentBlock? block;
    for (final b in blocks) {
      if (b.agentId == agentId) {
        block = b;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('子 agent 详情'),
      ),
      body: block == null
          ? Center(child: Text('子 agent 不存在或已被清理',
              style: TextStyle(color: t.textMuted)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _Section(label: '任务', child: SelectableText(
                  block.promptSummary.isEmpty ? '(无摘要)' : block.promptSummary,
                  style: TextStyle(color: t.text, fontSize: 14, height: 1.5),
                )),
                _Section(label: '状态', child: Row(
                  children: [
                    _statusChip(t, block.status),
                    const SizedBox(width: 8),
                    Text('${block.children.length} 步',
                        style: TextStyle(color: t.textMuted, fontSize: 12)),
                    if (block.parentToolUseId != null) ...[
                      const SizedBox(width: 8),
                      Text('parent: ${block.parentToolUseId!.substring(0, 8)}...',
                          style: TextStyle(color: t.textFaint, fontSize: 11)),
                    ],
                  ],
                )),
                if (block.children.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('暂无 thinking / tool 步骤',
                        style: TextStyle(color: t.textMuted, fontSize: 12)),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text('运行轨迹',
                        style: TextStyle(
                            color: t.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  ...block.children.map((c) => _ChildEntry(raw: c)),
                ],
                if (block.finalResult != null) ...[
                  const SizedBox(height: 12),
                  _Section(
                    label: '最终结果',
                    child: SelectableText(
                      _extractText(block.finalResult!),
                      style: TextStyle(
                          color: t.text, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _statusChip(ColorTokens t, String status) {
    final (label, color) = switch (status) {
      'running' => ('运行中', t.accent),
      'done' => ('已完成', t.success),
      'failed' => ('失败', t.danger),
      _ => (status, t.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _extractText(Map<String, dynamic> raw) {
    final msg = raw['message'];
    if (msg is! Map) return jsonEncode(raw);
    final content = msg['content'];
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final c in content) {
        if (c is Map) {
          if (c['type'] == 'text' && c['text'] is String) {
            buf.write(c['text']);
          } else if (c['type'] == 'tool_result' && c['content'] is String) {
            buf.write(c['content']);
          }
        }
      }
      return buf.toString();
    }
    return jsonEncode(raw);
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ChildEntry extends StatelessWidget {
  final Map<String, dynamic> raw;
  const _ChildEntry({required this.raw});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final msg = raw['message'];
    String kind = '?';
    String preview = '';
    if (msg is Map) {
      final content = msg['content'];
      if (content is String) {
        kind = 'text';
        preview = content;
      } else if (content is List) {
        for (final c in content) {
          if (c is Map) {
            final ty = c['type'] as String? ?? '';
            if (ty == 'thinking') {
              kind = 'thinking';
              preview = (c['thinking'] as String? ?? '').trim();
              break;
            }
            if (ty == 'text') {
              kind = 'text';
              preview = (c['text'] as String? ?? '').trim();
              break;
            }
            if (ty == 'tool_use') {
              kind = 'tool_use';
              final name = c['name'] as String? ?? '?';
              final inputStr = jsonEncode(c['input'] ?? {});
              preview = '$name · ${inputStr.length > 80 ? '${inputStr.substring(0, 80)}…' : inputStr}';
              break;
            }
            if (ty == 'tool_result') {
              kind = 'tool_result';
              final tc = c['content'];
              if (tc is String) {
                preview = tc;
              } else if (tc is List) {
                for (final tt in tc) {
                  if (tt is Map && tt['text'] is String) {
                    preview = tt['text'] as String;
                    break;
                  }
                }
              }
              break;
            }
          }
        }
      }
    }
    final color = switch (kind) {
      'thinking' => t.textFaint,
      'tool_use' => t.accent,
      'tool_result' => t.textMuted,
      'text' => t.text,
      _ => t.textMuted,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3, right: 8),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  preview,
                  style: TextStyle(color: t.text, fontSize: 12, height: 1.4),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
