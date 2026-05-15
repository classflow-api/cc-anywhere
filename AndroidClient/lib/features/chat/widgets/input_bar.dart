import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/chat_repository.dart';
import '../../../data/slash_command_repository.dart';
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

  /// 弹底部抽屉 — 宫图三入口:拍照 / 图片 / 文件。
  Future<void> _openAttachmentSheet() async {
    if (!widget.enabled) return;
    final result = await showModalBottomSheet<_AttachmentKind>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _AttachmentPickerSheet(),
    );
    if (result == null) return;
    switch (result) {
      case _AttachmentKind.camera:
        await _pickCamera();
        break;
      case _AttachmentKind.gallery:
        await _pickGallery();
        break;
      case _AttachmentKind.file:
        await _pickFile();
        break;
    }
  }

  Future<void> _pickCamera() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (shot == null) return;
    setState(() {
      if (_pending.length < 5) _pending.add(File(shot.path));
    });
  }

  Future<void> _pickGallery() async {
    final picked = await _picker.pickMultiImage(maxWidth: 2400, maxHeight: 2400);
    if (picked.isEmpty) return;
    setState(() {
      for (final f in picked) {
        if (_pending.length >= 5) break;
        _pending.add(File(f.path));
      }
    });
  }

  /// 弹底部抽屉 — 展示当前 tab 可用的 Claude Code slash commands,点选填入输入框。
  Future<void> _openSlashSheet() async {
    if (!widget.enabled) return;
    final repo = ref.read(slashCommandRepositoryProvider);
    // 主动请求一次最新列表(异步,sheet 内会监听 changes 更新)
    repo.requestList(widget.tabId);

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SlashCommandSheet(tabId: widget.tabId),
    );
    if (picked == null || picked.isEmpty) return;
    // 填入输入框 + 末尾空格便于继续输参数,光标停在末尾
    final inserted = '/$picked ';
    setState(() {
      _ctrl.text = inserted;
      _ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: inserted.length),
      );
    });
    _focus.requestFocus();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      // 任意文件 — Claude Code 能读大部分文本/代码/markdown/json/csv 等;
      // 二进制由 Claude 自己决定是否能处理,这里不做客户端限制。
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      for (final f in result.files) {
        if (_pending.length >= 5) break;
        if (f.path != null) _pending.add(File(f.path!));
      }
    });
  }

  Future<void> _send() async {
    if (!widget.enabled || _busy) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;
    // 立即清空 UI 上的输入(文字 + 图片预览),让用户感受到"已发送"的即时反馈。
    // chat_repository 会以本地 attachment / pending 文本卡片承接后续上传/发送状态,
    // 失败也由那些卡片显示(可重试/删除),无需把图片留在输入框预览里。
    final images = List<File>.of(_pending);
    setState(() {
      _busy = true;
      _pending.clear();
    });
    _ctrl.clear();
    try {
      if (images.isNotEmpty) {
        // 图片 + 文字(场景 2)。ChatRepository 内部会先串行上传图片,
        // 再在末尾发 input.text;上传过程通过本地 attachment pending 卡片显示进度。
        await ref.read(chatRepositoryProvider).sendTextWithImages(
              tabId: widget.tabId,
              text: text,
              images: images,
            );
      } else {
        // 纯文字(场景 1)
        await ref.read(chatRepositoryProvider).sendText(widget.tabId, text);
      }
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
                    icon: Icon(Icons.add_circle_outline_rounded,
                        size: 24, color: t.textMuted),
                    // _busy 期间禁用,避免上传中再选导致并发上传/界面 race
                    onPressed: widget.enabled && !_busy ? _openAttachmentSheet : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: '添加附件',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.terminal_rounded,
                        size: 22, color: t.textMuted),
                    onPressed: widget.enabled && !_busy ? _openSlashSheet : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    tooltip: '斜杠命令',
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

/// Slash commands 选择抽屉 — 监听 SlashCommandRepository,刷新最新列表,
/// 点选时通过 Navigator.pop 把 command name(不含 `/`)返回给调用方。
class _SlashCommandSheet extends ConsumerStatefulWidget {
  final String tabId;
  const _SlashCommandSheet({required this.tabId});

  @override
  ConsumerState<_SlashCommandSheet> createState() => _SlashCommandSheetState();
}

class _SlashCommandSheetState extends ConsumerState<_SlashCommandSheet> {
  late List<SlashCommand> _commands;
  StreamSubscription<MapEntry<String, List<SlashCommand>>>? _sub;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(slashCommandRepositoryProvider);
    _commands = repo.commands(widget.tabId);
    _sub = repo.changes.listen((entry) {
      if (entry.key != widget.tabId) return;
      if (!mounted) return;
      setState(() => _commands = entry.value);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 按 source 分组
    final groups = <String, List<SlashCommand>>{};
    for (final c in _commands) {
      groups.putIfAbsent(c.source.isEmpty ? 'other' : c.source, () => []).add(c);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        // builtin > user > project > plugin:*
        int order(String k) {
          if (k == 'builtin') return 0;
          if (k == 'user') return 1;
          if (k == 'project') return 2;
          return 3;
        }
        return order(a).compareTo(order(b));
      });

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 18, color: t.accent),
                  const SizedBox(width: 8),
                  Text('斜杠命令',
                      style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_commands.length} 个',
                      style: TextStyle(color: t.textFaint, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _commands.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 32),
                            CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                            const SizedBox(height: 12),
                            Text('正在从 Mac 端获取命令…',
                                style: TextStyle(color: t.textMuted, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: keys.length,
                        itemBuilder: (_, gi) {
                          final src = keys[gi];
                          final items = groups[src]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Text(
                                  _sourceLabel(src),
                                  style: TextStyle(
                                    color: t.textFaint,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              for (final c in items)
                                InkWell(
                                  onTap: () => Navigator.pop(context, c.name),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 10),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: t.accentSoft,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '/${c.name}',
                                            style: TextStyle(
                                              color: t.accent,
                                              fontSize: 12.5,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            c.description.isEmpty ? '—' : c.description,
                                            style: TextStyle(
                                                color: t.textMuted, fontSize: 12),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(String s) {
    if (s == 'builtin') return '内置';
    if (s == 'user') return '用户级 (~/.claude/commands/)';
    if (s == 'project') return '项目级';
    if (s.startsWith('plugin:')) return '插件 — ${s.substring(7)}';
    return s;
  }
}

enum _AttachmentKind { camera, gallery, file }

/// 底部宫图抽屉:拍照 / 图片 / 文件,模仿微信附件入口。
class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = <(_AttachmentKind, IconData, String)>[
      (_AttachmentKind.camera, Icons.photo_camera_outlined, '拍照'),
      (_AttachmentKind.gallery, Icons.photo_library_outlined, '图片'),
      (_AttachmentKind.file, Icons.insert_drive_file_outlined, '文件'),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: t.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              children: [
                for (final it in items)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, it.$1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: t.bgInset,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: t.line),
                          ),
                          child: Icon(it.$2, size: 26, color: t.accent),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          it.$3,
                          style: TextStyle(color: t.text, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
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

  static final _imageExts = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif'
  };

  bool get _isImage {
    final p = file.path.toLowerCase();
    final i = p.lastIndexOf('.');
    if (i < 0) return false;
    return _imageExts.contains(p.substring(i));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final basename = file.uri.pathSegments.isEmpty ? 'file' : file.uri.pathSegments.last;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _isImage
              ? Image.file(
                  file,
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _filePlaceholder(t, basename),
                )
              : _filePlaceholder(t, basename),
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

  Widget _filePlaceholder(ColorTokens t, String basename) {
    return Container(
      width: 70,
      height: 70,
      color: t.bgInset,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: t.textMuted, size: 22),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              basename,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(color: t.textFaint, fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
