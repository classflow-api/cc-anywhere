import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

/// 历史记录卡：仅在 ask 已被答完后由 message_card_list 渲染（pending 阶段
/// 由浮动 AskUserQuestionCardRealtime 接管，避免双卡冲突 — 用户反馈：
/// 既然有浮动卡，消息流就不需要再展示可交互的老版卡片，等回答完显示一个
/// "已回答"卡片就行）。
///
/// 渲染策略：精简单行 "Claude 提问 → 已回答" header + question 文本 +
/// 不展示 4 个选项 / 不展示输入框 / 不可交互。
class AskUserQuestionCard extends ConsumerWidget {
  final Message message;
  final String tabId;
  const AskUserQuestionCard(
      {super.key, required this.message, required this.tabId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final qs = message.questions ?? const [];
    // 取第一题的 question 作为摘要展示；多题场景仍记录在卡片内但不展开选项。
    final summary = qs.isNotEmpty
        ? (qs.first['question'] as String? ?? '历史提问')
        : '历史提问';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.bgInset,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.success.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 16, color: t.success),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Claude 提问 · 已回答',
                      style: TextStyle(
                          color: t.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(summary,
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}
