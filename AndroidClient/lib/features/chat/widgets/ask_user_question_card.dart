import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_repository.dart';
import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

/// Claude 的 AskUserQuestion 工具调用 — 在手机端展示成交互卡片:
/// 每条 question 一组,显示 header + question + 选项按钮列表。
/// 点击选项 → 把选中的 label 作为 input.text 发回 Mac 端 Claude,
/// Claude 将其作为用户对该问题的回答继续推进。
class AskUserQuestionCard extends ConsumerStatefulWidget {
  final Message message;
  final String tabId;
  const AskUserQuestionCard(
      {super.key, required this.message, required this.tabId});

  @override
  ConsumerState<AskUserQuestionCard> createState() =>
      _AskUserQuestionCardState();
}

class _AskUserQuestionCardState extends ConsumerState<AskUserQuestionCard> {
  /// 多选时记录已选项;单选选完直接发送。
  final Map<int, Set<String>> _multiSelections = {};
  /// 标记已发送过,卡片不再可点(避免误触发多轮)。
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final qs = widget.message.questions ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.bgElev,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.accent.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.question_answer_rounded, size: 16, color: t.accent),
                const SizedBox(width: 6),
                Text('Claude 提问',
                    style: TextStyle(
                        color: t.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_sent)
                  Text('已回复',
                      style: TextStyle(color: t.success, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < qs.length; i++) ..._questionBlock(t, i, qs[i]),
            if (!_sent && qs.any((q) => (q['multiSelect'] as bool? ?? false))) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitMultiSelections,
                  style: TextButton.styleFrom(
                    foregroundColor: t.accent,
                  ),
                  child: const Text('提交回答'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _questionBlock(ColorTokens t, int idx, Map<String, dynamic> q) {
    final header = q['header'] as String? ?? '';
    final question = q['question'] as String? ?? '';
    final multi = q['multiSelect'] as bool? ?? false;
    final opts = (q['options'] as List?)?.whereType<Map>().toList() ?? const [];
    final selected = _multiSelections.putIfAbsent(idx, () => <String>{});
    return [
      if (idx > 0) Divider(color: t.line, height: 18),
      if (header.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(header,
                style: TextStyle(
                    color: t.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      Text(question,
          style: TextStyle(
              color: t.text, fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      for (final opt in opts) _optionTile(t, idx, opt, selected, multi),
    ];
  }

  Widget _optionTile(ColorTokens t, int qIdx, Map opt, Set<String> selected,
      bool multiSelect) {
    final label = opt['label'] as String? ?? '';
    final desc = opt['description'] as String? ?? '';
    final isSelected = selected.contains(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _sent
            ? null
            : () {
                if (multiSelect) {
                  setState(() {
                    if (isSelected) {
                      selected.remove(label);
                    } else {
                      selected.add(label);
                    }
                  });
                } else {
                  // 单选立即发送
                  _submitSingle(qIdx, label);
                }
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? t.accentSoft : t.bgInset,
            border: Border.all(
              color: isSelected ? t.accent : t.line,
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (multiSelect)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: Icon(
                    isSelected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 16,
                    color: isSelected ? t.accent : t.textFaint,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(desc,
                          style: TextStyle(color: t.textMuted, fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitSingle(int qIdx, String label) {
    final qs = widget.message.questions ?? const [];
    final question = qs[qIdx]['question'] as String? ?? '';
    final answer = '【$question】我选: $label';
    _sendAnswer(answer);
  }

  void _submitMultiSelections() {
    final qs = widget.message.questions ?? const [];
    final parts = <String>[];
    for (var i = 0; i < qs.length; i++) {
      final question = qs[i]['question'] as String? ?? '';
      final multi = qs[i]['multiSelect'] as bool? ?? false;
      final selected = _multiSelections[i] ?? const <String>{};
      if (selected.isEmpty) continue;
      if (multi) {
        parts.add('【$question】我选: ${selected.join("、")}');
      } else {
        parts.add('【$question】我选: ${selected.first}');
      }
    }
    if (parts.isEmpty) return;
    _sendAnswer(parts.join('\n'));
  }

  Future<void> _sendAnswer(String text) async {
    setState(() => _sent = true);
    try {
      await ref.read(chatRepositoryProvider).sendText(widget.tabId, text);
    } catch (_) {
      if (mounted) setState(() => _sent = false);
    }
  }
}
