import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/chat_repository.dart';
import '../../data/tab_repository.dart';
import '../../data/ws_client.dart';
import '../../models/tab.dart';
import '../../services/ask_question_controller.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/pulse_dot.dart';
import '../../widgets/tool_progress_indicator.dart';
import 'widgets/ask_user_question_card_realtime.dart';
import 'widgets/input_bar.dart';
import 'widgets/message_card_list.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String tabId;
  final String? initialTabName;
  const ChatScreen({super.key, required this.tabId, this.initialTabName});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  /// 已弹过 snackbar 的 request_id,避免同一次 timeout 被 build 重复触发。
  final Set<String> _shownTimeoutToasts = {};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      final repo = ref.read(chatRepositoryProvider);
      repo.setActiveTab(widget.tabId);
      final cur = repo.snapshot(widget.tabId);
      if (cur == null || cur.messages.isEmpty) {
        repo.loadHistory(widget.tabId);
      }
    });
  }

  @override
  void dispose() {
    ref.read(chatRepositoryProvider).setActiveTab(null);
    super.dispose();
  }

  /// 监听 ask.question 实时态:超时弹一次 snackbar。
  void _maybeShowTimeoutToast(AskQuestionState ask) {
    final p = ask.pending;
    if (!ask.timedOut || p == null) return;
    if (_shownTimeoutToasts.contains(p.requestId)) return;
    _shownTimeoutToasts.add(p.requestId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('问题已超时'),
          duration: Duration(seconds: 2),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tabs = ref.watch(tabsStreamProvider).valueOrNull ?? const [];
    final tab = tabs.firstWhere(
      (e) => e.id == widget.tabId,
      orElse: () => TabInfo(
        id: widget.tabId,
        name: widget.initialTabName ?? widget.tabId,
        folder: '',
        claudeStatus: ClaudeStatus.unknown,
      ),
    );

    final chatAsync = ref.watch(tabChatStateProvider(widget.tabId));
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull;
    final macOnline = (ref.watch(macPresenceProvider).valueOrNull ?? MacPresence.unknown) ==
        MacPresence.online;
    final inputEnabled =
        wsState == WsConnectionState.connected && macOnline;

    final state = chatAsync.valueOrNull ??
        TabChatState(tabId: widget.tabId, messages: const []);

    // AskUserQuestion 实时模式状态(hook 桥接驱动)
    final askState =
        ref.watch(askQuestionStateProvider(widget.tabId)).valueOrNull ??
            AskQuestionState.empty;
    _maybeShowTimeoutToast(askState);
    final askPending = askState.pending;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(tab: tab),
            Expanded(
              child: chatAsync.when(
                data: (s) => MessageCardList(
                  tabId: widget.tabId,
                  state: s,
                  assistantTyping: state.assistantTyping,
                ),
                loading: () => state.messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : MessageCardList(tabId: widget.tabId, state: state),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '加载错误：$e',
                      style: TextStyle(color: t.danger),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            // 工具进度指示器 — 位于消息列表底部 / 输入栏上方。
            // 监听 tool.progress.pre/post 协议消息,运行中显示灰色进度条,
            // 失败时变红色 toast 5 秒后消失。详见 §3.4.3、§4.7.2。
            ToolProgressIndicator(tabId: widget.tabId),
            // 实时 AskUserQuestion 卡片:位于消息列表下、输入栏上,
            // pending 非空时显示;answered 后 controller 3s 后自动清空,
            // timeout 后立即清空并弹 snackbar。
            if (askPending != null)
              AskUserQuestionCardRealtime(
                key: ValueKey('ask_realtime_${askPending.requestId}'),
                payload: askPending,
                answered: askState.answered,
                // L4 R-F6：传递队列总长，N>=2 时卡片顶部显示 "1/N 待审批"
                queueCount: askState.queueCount,
                onSubmit: (answers) {
                  ref
                      .read(askQuestionControllerProvider)
                      .submit(widget.tabId, answers);
                },
                onDismiss: () {
                  ref
                      .read(askQuestionControllerProvider)
                      .dismiss(widget.tabId);
                },
                // F4 危险工具远程批准:tool_approval 分支专用回调,
                // 触发 ask.tool_approval.answer 协议消息 → server → mac winner 锁仲裁。
                onApprovalDecision: (decision) {
                  ref
                      .read(askQuestionControllerProvider)
                      .submitApproval(
                        widget.tabId,
                        requestId: askPending.requestId,
                        decision: decision,
                      );
                },
              ),
            InputBar(
              tabId: widget.tabId,
              enabled: inputEnabled,
              placeholder: '发消息给 ${tab.name}…',
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TabInfo tab;
  const _Header({required this.tab});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: t.bgInset,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back, size: 16, color: t.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tab.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    PulseDot(
                      color: switch (tab.claudeStatus) {
                        ClaudeStatus.running => t.success,
                        ClaudeStatus.error => t.danger,
                        _ => t.textFaint,
                      },
                      size: 6,
                      pulse: tab.claudeStatus == ClaudeStatus.running,
                    ),
                  ],
                ),
                if (tab.folder.isNotEmpty)
                  Text(
                    tab.folder,
                    style: TextStyle(
                      fontSize: 11,
                      color: t.textFaint,
                      fontFamily: 'monospace',
                    ),
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
