import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_repository.dart';
import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

/// tool_use 卡片 — 黄色边框 + diff 红绿 + 三按钮
class ToolUseCard extends ConsumerStatefulWidget {
  final Message message;
  final String tabId;
  const ToolUseCard({super.key, required this.message, required this.tabId});

  @override
  ConsumerState<ToolUseCard> createState() => _ToolUseCardState();
}

class _ToolUseCardState extends ConsumerState<ToolUseCard> {
  bool _busy = false;
  Timer? _timeoutTimer;
  String? _localStatus; // approved / rejected / always_approve

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _act(String action) async {
    setState(() {
      _busy = true;
      _localStatus = action;
    });
    try {
      await ref
          .read(chatRepositoryProvider)
          .approveToolUse(widget.tabId, action);
    } catch (_) {
      // 失败后回退
      setState(() {
        _busy = false;
        _localStatus = null;
      });
      return;
    }
    // 30s 超时回退
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _busy = false;
          _localStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('批准未生效（30s 超时）')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = widget.message;
    final showActions = m.toolStatus == ToolUseStatus.pending && _localStatus == null;
    final stateLabel = switch (m.toolStatus) {
      ToolUseStatus.approved => '已批准',
      ToolUseStatus.rejected => '已拒绝',
      ToolUseStatus.executed => '已执行',
      _ => null,
    } ?? (_localStatus != null ? '处理中…' : null);

    final input = m.toolInput ?? const {};
    final filePath = (input['file_path'] ?? input['path'] ?? '') as String?;
    final command = input['command'] as String?;
    final diffOld = input['old_string'] as String?;
    final diffNew = input['new_string'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToolIcon(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${m.toolName ?? 'Tool'} · ${stateLabel ?? '待批准'}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.warn.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'TOOL_USE',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: t.warn,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.bgElev,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                        border: Border.all(color: t.warn),
                        boxShadow: [
                          BoxShadow(
                            color: t.warn.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (filePath != null && filePath.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.description_outlined,
                                    size: 14, color: t.accent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    filePath,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: t.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          if (command != null) ...[
                            const SizedBox(height: 8),
                            _CodeBlock(text: command, color: t.text),
                          ],
                          if (diffOld != null || diffNew != null) ...[
                            const SizedBox(height: 10),
                            _DiffBlock(oldText: diffOld, newText: diffNew),
                          ],
                          if (showActions) ...[
                            const SizedBox(height: 12),
                            _ActionRow(
                              onApprove: () => _act('approve'),
                              onReject: () => _act('reject'),
                              onAlways: () => _act('always_approve'),
                              busy: _busy,
                            ),
                          ] else if (stateLabel != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 16, color: t.success),
                                const SizedBox(width: 6),
                                Text(stateLabel,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: t.success,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_busy)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            color: t.bg.withValues(alpha: 0.55),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: t.accent),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: t.warn,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.edit_rounded, size: 13, color: Color(0xFF3A2700)),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;
  final Color color;
  const _CodeBlock({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          color: color,
          height: 1.5,
        ),
      ),
    );
  }
}

class _DiffBlock extends StatelessWidget {
  final String? oldText;
  final String? newText;
  const _DiffBlock({required this.oldText, required this.newText});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lines = <_DiffLine>[];
    if (oldText != null && oldText!.isNotEmpty) {
      for (final l in const LineSplitter().convert(oldText!)) {
        lines.add(_DiffLine('- $l', t.danger));
      }
    }
    if (newText != null && newText!.isNotEmpty) {
      for (final l in const LineSplitter().convert(newText!)) {
        lines.add(_DiffLine('+ $l', t.success));
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Text(
              l.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: l.color,
                height: 1.55,
              ),
            ),
        ],
      ),
    );
  }
}

class _DiffLine {
  final String text;
  final Color color;
  _DiffLine(this.text, this.color);
}

class _ActionRow extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onAlways;
  final bool busy;
  const _ActionRow({
    required this.onApprove,
    required this.onReject,
    required this.onAlways,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: _PrimaryButton(
            label: '批准',
            icon: Icons.check_rounded,
            bg: t.success,
            fg: const Color(0xFF001A0D),
            onTap: busy ? null : onApprove,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SecondaryButton(
            label: '拒绝',
            icon: Icons.close_rounded,
            onTap: busy ? null : onReject,
          ),
        ),
        const SizedBox(width: 8),
        _SecondaryButton(
          label: '总是',
          icon: null,
          onTap: busy ? null : onAlways,
          compact: true,
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: bg.withValues(alpha: 0.5),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: -8,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool compact;
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.bgInset,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: t.text),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: t.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

