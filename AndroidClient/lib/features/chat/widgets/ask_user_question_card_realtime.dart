import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/protocol_message.dart';
import '../../../theme/color_tokens.dart';

/// AskUserQuestion 实时模式卡片(L4 阶段七 T13)。
///
/// 与 `AskUserQuestionCard`(事后模式,从 JSONL 解析展示)不同,本 widget 由 hook 桥接
/// 实时驱动:接收 `ask.question.pending` payload 并交互。生命周期由外层
/// `AskQuestionController` 控制,本 widget 只负责 UI + 回调。
///
/// 业务规则对齐:
/// - R-F1-012:始终展示"自定义回答"输入项(payload.allowOther 缺失时默认 true)
/// - R-F1-013:外层注入 `answeredBy` 后禁用所有提交按钮
/// - R-F1-014:answers 值类型不区分 label 字符串与 Other 任意字符串
/// - 需求规格说明书 C-5:Other 输入框限长 200 字符
/// - F4(危险工具远程批准):askKind == 'tool_approval' 时切换到"工具批准"模式:
///   不渲染 questions,改渲染工具徽章 + 工具名 + tool_input 摘要 + 允许/拒绝双按钮,
///   通过 onApprovalDecision 上抛 decision。该路径下 questions 通常为空。
class AskUserQuestionCardRealtime extends StatefulWidget {
  final AskQuestionPendingPayload payload;
  /// 当前是否已被回答(answered != null 时禁用所有提交按钮,显示 winner)
  final AskQuestionAnsweredPayload? answered;
  /// 用户提交答案(label 字符串或 Other 输入文字),用于 user_question 模式。
  final void Function(Map<String, String> answers) onSubmit;
  /// 用户主动 dismiss(取消 / 已被回答倒计时结束 / 超时)
  final VoidCallback onDismiss;
  /// 用户对 tool_approval 模式做出 decision(allow / deny)。仅 askKind==
  /// 'tool_approval' 时使用;为兼容老调用方,本回调可空,空则该模式只展示不可交互。
  final void Function(String decision)? onApprovalDecision;

  const AskUserQuestionCardRealtime({
    super.key,
    required this.payload,
    required this.onSubmit,
    required this.onDismiss,
    this.answered,
    this.onApprovalDecision,
  });

  @override
  State<AskUserQuestionCardRealtime> createState() =>
      _AskUserQuestionCardRealtimeState();
}

class _AskUserQuestionCardRealtimeState
    extends State<AskUserQuestionCardRealtime> {
  /// 多选时记录每题已选 label 集合;单选选中后直接发送。
  final Map<int, Set<String>> _multiSelections = {};

  /// Other 自定义输入:每题独立 controller + 是否处于展开输入态。
  final Map<int, TextEditingController> _otherControllers = {};
  final Map<int, bool> _otherExpanded = {};

  /// 标记已发送过 — 卡片置 disabled,等待 answered/timeout 回执。
  bool _submitting = false;

  bool get _locked => widget.answered != null || _submitting;

  @override
  void dispose() {
    for (final c in _otherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final qs = widget.payload.questions;
    final answered = widget.answered;
    final isToolApproval = widget.payload.askKind == 'tool_approval';
    // 工具批准模式:边框使用红色(danger)以提示风险;答完后保持成功色。
    final borderColor = answered != null
        ? t.success.withValues(alpha: 0.6)
        : (isToolApproval
            ? t.danger.withValues(alpha: 0.7)
            : t.accent.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.bgElev,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(t, answered),
            const SizedBox(height: 8),
            if (isToolApproval)
              ..._buildToolApprovalBody(t, answered)
            else ...[
              for (int i = 0; i < qs.length; i++)
                ..._questionBlock(t, i, qs[i]),
              if (answered == null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : widget.onDismiss,
                      style: TextButton.styleFrom(foregroundColor: t.textMuted),
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    if (qs.any((q) => (q['multiSelect'] as bool? ?? false)))
                      TextButton(
                        onPressed: _locked ? null : _submitMultiSelections,
                        style: TextButton.styleFrom(foregroundColor: t.accent),
                        child: const Text('提交回答'),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorTokens t, AskQuestionAnsweredPayload? answered) {
    final isToolApproval = widget.payload.askKind == 'tool_approval';
    final toolName = widget.payload.toolName ?? '';
    final title = answered != null
        ? '已被 ${answered.answeredBy.isEmpty ? "其他端" : answered.answeredBy} 回答'
        : (isToolApproval
            ? (toolName.isEmpty
                ? 'Claude 请求工具批准'
                : 'Claude 想执行 $toolName')
            : 'Claude 提问');
    // 工具批准模式未答时用红色 danger,与边框/按钮一致传递风险信号(§3.4.1)
    final color = answered != null
        ? t.success
        : (isToolApproval ? t.danger : t.accent);
    return Row(
      children: [
        Icon(
          isToolApproval ? Icons.warning_amber_rounded : Icons.question_answer_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        if (isToolApproval && answered == null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '工具批准',
              style: TextStyle(
                color: t.danger,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '实时',
          style: TextStyle(
            color: t.textFaint,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  List<Widget> _questionBlock(ColorTokens t, int idx, Map<String, dynamic> q) {
    final header = q['header'] as String? ?? '';
    final question = q['question'] as String? ?? '';
    final multi = q['multiSelect'] as bool? ?? false;
    final opts = (q['options'] as List?)?.whereType<Map>().toList() ?? const [];
    final selected = _multiSelections.putIfAbsent(idx, () => <String>{});
    final answered = widget.answered;
    final lockedAnswer = answered?.answers[question];
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
            child: Text(
              header,
              style: TextStyle(
                color: t.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      Text(
        question,
        style: TextStyle(
          color: t.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      if (lockedAnswer != null)
        _lockedAnswerTile(t, lockedAnswer)
      else ...[
        for (final opt in opts)
          _optionTile(t, idx, opt, selected, multi, question),
        // R-F1-012:始终展示"自定义回答"输入项(allow_other 默认 true)。
        if (widget.payload.allowOther)
          _otherInputTile(t, idx, question, multi),
      ],
    ];
  }

  Widget _lockedAnswerTile(ColorTokens t, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.bgInset,
          border: Border.all(color: t.success.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 14, color: t.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: t.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(
    ColorTokens t,
    int qIdx,
    Map opt,
    Set<String> selected,
    bool multiSelect,
    String question,
  ) {
    final label = opt['label'] as String? ?? '';
    final desc = opt['description'] as String? ?? '';
    final isSelected = selected.contains(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _locked
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
                  _submitSingle(question, label);
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
                    Text(
                      label,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: TextStyle(color: t.textMuted, fontSize: 11.5),
                      ),
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

  Widget _otherInputTile(
    ColorTokens t,
    int qIdx,
    String question,
    bool multiSelect,
  ) {
    final expanded = _otherExpanded[qIdx] ?? false;
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _locked
              ? null
              : () {
                  setState(() => _otherExpanded[qIdx] = true);
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: t.bgInset,
              border: Border.all(
                color: t.line,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded, size: 16, color: t.textFaint),
                const SizedBox(width: 6),
                Text(
                  '自定义回答',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final controller = _otherControllers.putIfAbsent(
      qIdx,
      () => TextEditingController(),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: t.bgInset,
          border: Border.all(color: t.accent.withValues(alpha: 0.6), width: 1.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.edit_note_rounded, size: 16, color: t.accent),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !_locked,
                autofocus: true,
                maxLength: 200, // C-5:Other 输入框限长 200 字符
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(200),
                ],
                style: TextStyle(color: t.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '输入自定义回答(最长 200 字)',
                  hintStyle: TextStyle(color: t.textFaint, fontSize: 12.5),
                  isDense: true,
                  border: InputBorder.none,
                  counterText: '',
                ),
                onSubmitted: (_) => _submitOther(qIdx, question, multiSelect),
              ),
            ),
            IconButton(
              tooltip: '提交',
              icon: Icon(Icons.send_rounded, size: 18, color: t.accent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: _locked
                  ? null
                  : () => _submitOther(qIdx, question, multiSelect),
            ),
          ],
        ),
      ),
    );
  }

  void _submitSingle(String question, String label) {
    _send({question: label});
  }

  void _submitOther(int qIdx, String question, bool multiSelect) {
    final controller = _otherControllers[qIdx];
    final text = (controller?.text ?? '').trim();
    if (text.isEmpty) return;
    if (multiSelect) {
      // 多选场景:Other 文字按"提交回答"统一提交时合并;此处先把 text 塞入 selected。
      final selected = _multiSelections.putIfAbsent(qIdx, () => <String>{});
      setState(() {
        selected.add(text);
        _otherExpanded[qIdx] = false;
        controller?.clear();
      });
      return;
    }
    _send({question: text});
  }

  void _submitMultiSelections() {
    final qs = widget.payload.questions;
    final answers = <String, String>{};
    for (var i = 0; i < qs.length; i++) {
      final question = qs[i]['question'] as String? ?? '';
      final multi = qs[i]['multiSelect'] as bool? ?? false;
      final selected = _multiSelections[i] ?? const <String>{};
      // 多选 → 顿号拼接(对齐事后模式行为)
      // 单选 → 取第一个 selected
      if (selected.isEmpty) {
        // 多题场景:未答的题用 Other 输入兜底
        final txt = (_otherControllers[i]?.text ?? '').trim();
        if (txt.isNotEmpty) {
          answers[question] = txt;
        }
        continue;
      }
      answers[question] = multi ? selected.join('、') : selected.first;
    }
    if (answers.isEmpty) return;
    _send(answers);
  }

  void _send(Map<String, String> answers) {
    if (_submitting || widget.answered != null) return;
    setState(() => _submitting = true);
    widget.onSubmit(answers);
  }

  // ===== F4 危险工具远程批准:tool_approval body =====

  /// 工具批准模式 body:渲染 tool_input 摘要 + 允许/拒绝 双按钮。
  /// 已 answered → 折叠为只读 "已批准/已拒绝" tile;未 answered → 双按钮。
  List<Widget> _buildToolApprovalBody(
    ColorTokens t,
    AskQuestionAnsweredPayload? answered,
  ) {
    final summary = _toolApprovalSummary(widget.payload);
    return [
      // 摘要区:等宽字体展示,与 Mac 端 ask card 风格一致
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.bgInset,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          summary,
          style: TextStyle(
            color: t.text,
            fontSize: 12.5,
            height: 1.4,
            fontFamily: 'monospace',
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (answered == null)
        Row(
          children: [
            TextButton(
              onPressed: _submitting ? null : widget.onDismiss,
              style: TextButton.styleFrom(foregroundColor: t.textMuted),
              child: const Text('忽略'),
            ),
            const Spacer(),
            OutlinedButton.icon(
              icon: Icon(Icons.block_rounded, size: 16, color: t.danger),
              label: Text('拒绝', style: TextStyle(color: t.danger)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.danger.withValues(alpha: 0.6)),
              ),
              onPressed: _locked ? null : () => _submitApproval('deny'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('允许'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.success,
                foregroundColor: Colors.white,
              ),
              onPressed: _locked ? null : () => _submitApproval('allow'),
            ),
          ],
        ),
    ];
  }

  void _submitApproval(String decision) {
    if (_submitting || widget.answered != null) return;
    final cb = widget.onApprovalDecision;
    if (cb == null) return;
    setState(() => _submitting = true);
    cb(decision);
  }

  /// 根据 tool_name 与 tool_input 生成摘要文本。
  ///
  /// Mac 端已把 tool_input 内长字符串截到 500 字符(R-F4-004),
  /// 这里只做 tool 名特化抽取与最外层兜底:
  /// - `Bash`       → `$ {command}`
  /// - `Write`      → `{file_path}\n\n{content 截 400 字}`
  /// - `Edit`       → `{file_path}\n- {old_string 首行}\n+ {new_string 首行}`
  /// - `MultiEdit`  → `{file_path}\n+ N 处替换`
  /// - 兜底         → tool_input 的 JSON 短化(单行)
  String _toolApprovalSummary(AskQuestionPendingPayload payload) {
    final toolName = (payload.toolName ?? '').trim();
    final input = payload.toolInput ?? const <String, dynamic>{};
    String s;
    switch (toolName) {
      case 'Bash':
        final cmd = (input['command'] as String?)?.trim() ?? '';
        s = cmd.isEmpty ? '(空命令)' : '\$ $cmd';
        break;
      case 'Write':
        final path = (input['file_path'] as String?)?.trim() ?? '';
        final content = (input['content'] as String?) ?? '';
        s = '${path.isEmpty ? "(无路径)" : path}\n\n'
            '${_clamp(content, 400)}';
        break;
      case 'Edit':
        final path = (input['file_path'] as String?)?.trim() ?? '';
        final oldStr = (input['old_string'] as String?) ?? '';
        final newStr = (input['new_string'] as String?) ?? '';
        s = '${path.isEmpty ? "(无路径)" : path}\n'
            '- ${_firstLine(oldStr)}\n'
            '+ ${_firstLine(newStr)}';
        break;
      case 'MultiEdit':
        final path = (input['file_path'] as String?)?.trim() ?? '';
        final edits = input['edits'];
        final count = edits is List ? edits.length : 0;
        s = '${path.isEmpty ? "(无路径)" : path}\n+ $count 处替换';
        break;
      default:
        // 兜底:Map → 单行 key=value 罗列,避免巨型 JSON 占满屏幕
        if (input.isEmpty) {
          s = '(无参数)';
        } else {
          final pairs = <String>[];
          input.forEach((k, v) {
            final vs = v is String ? v : v.toString();
            pairs.add('$k=${_clamp(vs, 80)}');
          });
          s = pairs.join(' ; ');
        }
    }
    // 兜底再截一刀,防止 Mac 端 truncate 失灵时手机被卡死
    return _clamp(s, 800);
  }

  String _clamp(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}…';
  }

  String _firstLine(String s) {
    final i = s.indexOf('\n');
    final line = i < 0 ? s : s.substring(0, i);
    return _clamp(line, 120);
  }
}
