// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// sub_agent_runner_bar.dart
// 底部固定的 sub-agent 运行状态栏(类似 mac TUI 的 "Running N agents..." )。
// 嵌入 chat_screen 的 InputBar 上方,跟输入框分隔开,不污染聊天流。
// 监听 ChatRepository.watchSubAgents(tabId),实时刷新 running 子 agent 列表。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_repository.dart';
import '../../../theme/color_tokens.dart';
import 'sub_agent_folded_block.dart';
import 'sub_agent_detail_screen.dart';

final _subAgentsStreamProvider = StreamProvider.family<List<SubAgentBlock>, String>(
  (ref, tabId) => ref.watch(chatRepositoryProvider).watchSubAgents(tabId),
);

class SubAgentRunnerBar extends ConsumerWidget {
  final String tabId;
  const SubAgentRunnerBar({super.key, required this.tabId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(_subAgentsStreamProvider(tabId));
    final all = async.valueOrNull ?? const <SubAgentBlock>[];
    // 只显示运行中的 sub-agent;done/failed 不在底部栏(完成态本身就该走聊天流)
    final running = all.where((b) => b.status == 'running').toList();
    if (running.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accent.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(t.accent),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Running ${running.length} agent${running.length > 1 ? 's' : ''}',
                style: TextStyle(
                  color: t.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...running.map((b) => _RunnerRow(block: b, tabId: tabId)),
        ],
      ),
    );
  }
}

class _RunnerRow extends StatelessWidget {
  final SubAgentBlock block;
  final String tabId;
  const _RunnerRow({required this.block, required this.tabId});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 取最近一条 tool_use 的工具名作为"当前在干啥"
    String? currentTool;
    for (final child in block.children.reversed) {
      final msg = child['message'];
      if (msg is! Map) continue;
      final content = msg['content'];
      if (content is! List) continue;
      for (final c in content) {
        if (c is Map && c['type'] == 'tool_use' && c['name'] is String) {
          currentTool = c['name'] as String;
          break;
        }
      }
      if (currentTool != null) break;
    }

    final subject = block.promptSummary.isEmpty
        ? '子 agent #${block.agentId}'
        : block.promptSummary;
    final stepText = '${block.children.length} 步';
    final tail = currentTool != null ? '$stepText · $currentTool' : stepText;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SubAgentDetailScreen(tabId: tabId, agentId: block.agentId),
        ));
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Icon(Icons.bolt, size: 12, color: t.accent),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    style: TextStyle(color: t.text, fontSize: 12, height: 1.3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    tail,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: t.textFaint),
          ],
        ),
      ),
    );
  }
}
