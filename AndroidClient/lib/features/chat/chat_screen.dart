import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/chat_repository.dart';
import '../../data/tab_repository.dart';
import '../../data/ws_client.dart';
import '../../models/tab.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/pulse_dot.dart';
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
