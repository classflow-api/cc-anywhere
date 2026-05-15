import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_repository.dart';
import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';
import 'ask_user_question_card.dart';
import 'assistant_text_card.dart';
import 'attachment_card.dart';
import 'raw_card.dart';
import 'thinking_card.dart';
import 'time_separator.dart';
import 'tool_result_card.dart';
import 'tool_use_card.dart';
import 'typing_dots.dart';
import 'user_card.dart';

/// 消息列表 — 自动滚动到底部，向上拉加载更多，新消息 FAB
class MessageCardList extends ConsumerStatefulWidget {
  final String tabId;
  final TabChatState state;
  final bool assistantTyping;

  const MessageCardList({
    super.key,
    required this.tabId,
    required this.state,
    this.assistantTyping = false,
  });

  @override
  ConsumerState<MessageCardList> createState() => _MessageCardListState();
}

class _MessageCardListState extends ConsumerState<MessageCardList> {
  final _scrollCtrl = ScrollController();
  int _newSinceFocus = 0;
  bool _atBottom = true;
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void didUpdateWidget(covariant MessageCardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newLen = widget.state.messages.length;
    if (newLen > _lastMsgCount) {
      final delta = newLen - _lastMsgCount;
      if (_atBottom) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom(animate: true));
      } else {
        _newSinceFocus += delta;
      }
    }
    _lastMsgCount = newLen;
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final pos = _scrollCtrl.position.pixels;
    final atBottom = (max - pos) < 80;
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _newSinceFocus = 0;
      });
    }
    // 触顶加载更多
    if (pos < 30 && widget.state.hasMore && !widget.state.loadingMore) {
      final first = widget.state.messages.firstOrNull;
      ref
          .read(chatRepositoryProvider)
          .loadHistory(widget.tabId, before: first?.timestamp);
    }
  }

  void _jumpToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  void _scrollToBottom({bool animate = false}) {
    if (!_scrollCtrl.hasClients) return;
    final target = _scrollCtrl.position.maxScrollExtent;
    if (animate) {
      _scrollCtrl.animateTo(target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut);
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = widget.state.messages;
    // 仅生成元数据(message + 可选 separator 时间标记),不预实例化 Widget。
    // ListView.builder 的 itemBuilder 才真正按需 lazy 创建,避免 N 条消息时
    // 整列表都被实例化导致滑动卡顿。
    final renderMeta = _computeRenderMeta(items);

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          // cacheExtent 提高一点能减少滑动到边界时的 build 抖动,但太大反而增加内存。
          cacheExtent: 600,
          itemCount: renderMeta.length +
              (widget.state.loadingMore ? 1 : 0) +
              (widget.assistantTyping ? 1 : 0),
          itemBuilder: (_, i) {
            // header: loading more
            if (widget.state.loadingMore && i == 0) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final offset = widget.state.loadingMore ? 1 : 0;
            final idx = i - offset;
            if (idx < renderMeta.length) {
              final meta = renderMeta[idx];
              if (meta.separatorTime != null) {
                return TimeSeparator(time: meta.separatorTime!);
              }
              return _buildCard(meta.message!);
            }
            // assistant typing
            return _AssistantTyping();
          },
        ),
        // 新消息 FAB
        if (!_atBottom)
          Positioned(
            right: 16,
            bottom: 16,
            child: GestureDetector(
              onTap: () => _scrollToBottom(animate: true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.bgElev,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: t.line),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_downward_rounded,
                        size: 14, color: t.accent),
                    if (_newSinceFocus > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$_newSinceFocus 条新消息',
                        style: TextStyle(
                          color: t.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 计算渲染项元数据(message 或 separator 标记),不实例化 Widget。
  /// 真正的 Widget 由 ListView.builder 的 itemBuilder lazy 创建。
  List<({Message? message, DateTime? separatorTime})> _computeRenderMeta(
      List<Message> items) {
    final out = <({Message? message, DateTime? separatorTime})>[];
    DateTime? prev;
    for (final m in items) {
      if (prev == null || m.timestamp.difference(prev).inMinutes >= 60) {
        out.add((message: null, separatorTime: m.timestamp));
      }
      out.add((message: m, separatorTime: null));
      prev = m.timestamp;
    }
    return out;
  }

  Widget _buildCard(Message m) {
    switch (m.kind) {
      case MessageKind.text:
        if (m.role == MessageRole.user) {
          return UserCard(
            key: ValueKey(m.uuid),
            message: m,
            onRetry: m.sendFailed
                ? () => ref
                    .read(chatRepositoryProvider)
                    .sendText(widget.tabId, m.text ?? '')
                : null,
          );
        }
        return AssistantTextCard(key: ValueKey(m.uuid), message: m);
      case MessageKind.thinking:
        return ThinkingCard(key: ValueKey(m.uuid), message: m);
      case MessageKind.toolUse:
        return ToolUseCard(
            key: ValueKey(m.uuid), message: m, tabId: widget.tabId);
      case MessageKind.toolResult:
        return ToolResultCard(key: ValueKey(m.uuid), message: m);
      case MessageKind.attachment:
        return AttachmentCard(key: ValueKey(m.uuid), message: m);
      case MessageKind.askUserQuestion:
        return AskUserQuestionCard(
          key: ValueKey(m.uuid),
          message: m,
          tabId: widget.tabId,
        );
      case MessageKind.raw:
        return RawCard(key: ValueKey(m.uuid), message: m);
    }
  }
}

class _AssistantTyping extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.assistantAvatarStart, t.accent],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 13, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.bgElev,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(color: t.line),
            ),
            child: const TypingDots(),
          ),
        ],
      ),
    );
  }
}
