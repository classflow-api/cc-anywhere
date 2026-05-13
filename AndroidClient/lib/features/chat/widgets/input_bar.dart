import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/chat_repository.dart';
import '../../../theme/color_tokens.dart';

/// 底部输入栏 — 文本 + 图片选择 + 发送按钮
class InputBar extends ConsumerStatefulWidget {
  final String tabId;
  final bool enabled;
  final String? placeholder;
  const InputBar({
    super.key,
    required this.tabId,
    this.enabled = true,
    this.placeholder,
  });

  @override
  ConsumerState<InputBar> createState() => _InputBarState();
}

class _InputBarState extends ConsumerState<InputBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  final List<File> _pending = [];
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (!widget.enabled) return;
    final picked = await _picker.pickMultiImage(maxWidth: 2400, maxHeight: 2400);
    if (picked.isEmpty) return;
    setState(() {
      for (final f in picked) {
        if (_pending.length >= 5) break;
        _pending.add(File(f.path));
      }
    });
  }

  Future<void> _send() async {
    if (!widget.enabled || _busy) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;
    setState(() => _busy = true);
    // 复制一份以便清空 _pending 后 ChatRepository 仍能引用
    final images = List<File>.of(_pending);
    try {
      if (images.isNotEmpty) {
        // 图片 + 文字（场景 2）。ChatRepository 内部会先串行上传图片，
        // 再在末尾发 input.text；上传过程通过本地 attachment pending 卡片显示进度。
        await ref.read(chatRepositoryProvider).sendTextWithImages(
              tabId: widget.tabId,
              text: text,
              images: images,
            );
      } else {
        // 纯文字（场景 1）
        await ref.read(chatRepositoryProvider).sendText(widget.tabId, text);
      }
      _ctrl.clear();
      if (mounted) setState(() => _pending.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(top: BorderSide(color: t.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pending.isNotEmpty) ...[
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pending.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _Thumb(
                    file: _pending[i],
                    onRemove: () => setState(() => _pending.removeAt(i)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              decoration: BoxDecoration(
                color: t.bgInset,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: t.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.image_outlined,
                        size: 22, color: t.textMuted),
                    onPressed: widget.enabled ? _pick : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      maxLength: 4000,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(color: t.text, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: widget.enabled
                            ? (widget.placeholder ?? '发消息…')
                            : '未连接 Server',
                        hintStyle: TextStyle(color: t.textFaint, fontSize: 14),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.enabled && !_busy ? _send : null,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: widget.enabled
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [t.accent, t.accentGradEnd],
                              )
                            : null,
                        color: widget.enabled ? null : t.line,
                        shape: BoxShape.circle,
                        boxShadow: widget.enabled
                            ? [
                                BoxShadow(
                                  color: t.accent.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                  spreadRadius: -4,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.send_rounded,
                        size: 16,
                        color: widget.enabled ? t.accentFg : t.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;
  const _Thumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            width: 70,
            height: 70,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 70,
              height: 70,
              color: t.bgInset,
              child: Icon(Icons.broken_image_outlined, color: t.textFaint),
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
