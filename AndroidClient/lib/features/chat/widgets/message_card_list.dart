import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/chat_repository.dart';
import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';
import 'ask_user_question_card.dart';
import 'assistant_text_card.dart';
import 'attachment_card.dart';
import 'raw_card.dart';
import 'sub_agent_folded_block.dart';
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

  /// 首次进入聊天界面是否已完成初始滚到底（防止重复触发）。
  bool _initialScrollDone = false;

  /// `_scheduleInitialJump` 排程的可取消 timer 列表。dispose 时统一 cancel，
  /// 避免 widget unmount 期间 closure 仍然 fire 撞 RenderObject `_owner != null`
  /// assertion（场景：用户进入空聊天页 < 450ms 内立即返回）。
  final List<Timer> _initJumpTimers = [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // 进入聊天界面立即多帧 retry 跳到底（ListView lazy build + 异步数据加载
    // 导致首帧 maxScrollExtent 可能 = 0，需要多帧 retry 兜底）。
    _scheduleInitialJump();
  }

  @override
  void didUpdateWidget(covariant MessageCardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newLen = widget.state.messages.length;
    if (newLen > _lastMsgCount) {
      final delta = newLen - _lastMsgCount;
      if (!_initialScrollDone) {
        // 首次拿到非空消息列表 → 瞬间到底（用户进入聊天即在最新消息位置）
        _scheduleInitialJump();
      } else if (_atBottom) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom(animate: true));
      } else {
        _newSinceFocus += delta;
      }
    }
    _lastMsgCount = newLen;
  }

  /// 在 0/80/200/400ms 各跳一次，确保异步加载完成 + layout 稳定后真到底。
  /// 用可取消的 Timer 而非 Future.delayed —— 后者无法取消，widget 已 unmount
  /// 但 dispose 还没跑的窗口期内 closure 仍可能触发，撞 RenderObject `_owner`
  /// assertion。
  void _scheduleInitialJump() {
    for (final ms in const [0, 80, 200, 400]) {
      _initJumpTimers.add(Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _jumpToBottom();
      }));
    }
    // 最后一次 retry 完后标记完成（之后走正常 didUpdateWidget 滚动逻辑）
    _initJumpTimers.add(Timer(const Duration(milliseconds: 450), () {
      if (mounted) _initialScrollDone = true;
    }));
  }

  @override
  void dispose() {
    for (final t in _initJumpTimers) {
      t.cancel();
    }
    _initJumpTimers.clear();
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
    final pos = _scrollCtrl.position;
    // ListView 已 layout 完毕才有 content dimensions；timer fire 时如果对应
    // RenderObject 已 detach（unmount 中间态），hasContentDimensions = false，
    // 此处直接 noop 而非访问 maxScrollExtent 触发 _owner assertion。
    if (!pos.hasContentDimensions) return;
    _scrollCtrl.jumpTo(pos.maxScrollExtent);
  }

  void _scrollToBottom({bool animate = false}) {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (!pos.hasContentDimensions) return;
    final target = pos.maxScrollExtent;
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
      case MessageKind.subAgentBlock:
        // L4：placeholder Message uuid 形如 'subagent-<tabId>-<key>'，
        // 反查 ChatRepository._subAgentBlocks 拿到真正的 block 数据后渲染。
        // 解析失败（理论不发生）退化为空 SizedBox，避免空卡污染主流。
        final prefix = 'subagent-${widget.tabId}-';
        if (!m.uuid.startsWith(prefix)) {
          return const SizedBox.shrink();
        }
        final key = m.uuid.substring(prefix.length);
        final block = ref
            .read(chatRepositoryProvider)
            .lookupSubAgentBlock(widget.tabId, key);
        if (block == null) return const SizedBox.shrink();
        return SubAgentFoldedBlock(key: ValueKey(m.uuid), block: block);
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
        // 双卡显示治理：浮动 realtime card（chat_screen 渲染）负责 pending 阶段的交互。
        // 消息流里只在 ask "已答完" 后才作为历史记录展示一个精简卡，未答完直接隐藏。
        // 判定方式：查找 messages 中是否存在 tool_use_id 与本 ask 匹配的 toolResult。
        final tuid = m.toolUseId;
        if (tuid == null || tuid.isEmpty) {
          // 没 tool_use_id 无法配对，保守隐藏（pending 由浮动卡显示）
          return const SizedBox.shrink();
        }
        final result = widget.state.messages.firstWhere(
          (x) => x.kind == MessageKind.toolResult && x.toolUseId == tuid,
          orElse: () => m, // sentinel
        );
        if (identical(result, m)) {
          // 未找到配对 toolResult → ask 还在 pending，隐藏让浮动卡接管
          return const SizedBox.shrink();
        }
        // 已答完：渲染精简"已回答"记录卡
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
