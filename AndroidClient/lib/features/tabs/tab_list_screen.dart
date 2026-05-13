import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/tab_repository.dart';
import '../../data/ws_client.dart';
import '../../models/tab.dart';
import '../../routes/app_router.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/pulse_dot.dart';

/// 会话列表页 — 1:1 对应 mobile-client.jsx MobileTabList
class TabListScreen extends ConsumerStatefulWidget {
  const TabListScreen({super.key});

  @override
  ConsumerState<TabListScreen> createState() => _TabListScreenState();
}

class _TabListScreenState extends ConsumerState<TabListScreen> {
  @override
  void initState() {
    super.initState();
    // 进入时主动请求一次
    Future<void>.microtask(() {
      ref.read(tabRepositoryProvider).requestList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tabsAsync = ref.watch(tabsStreamProvider);
    final presence = ref.watch(macPresenceProvider).valueOrNull ?? MacPresence.unknown;
    final connState = ref.watch(wsConnectionStateProvider).valueOrNull;
    final macOnline = presence == MacPresence.online;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _Header(
                  macOnline: macOnline,
                  connectionStatus: _formatConnectionStatus(connState),
                  count: tabsAsync.valueOrNull?.length ?? 0,
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: t.accent,
                    backgroundColor: t.bgElev,
                    onRefresh: () =>
                        ref.read(tabRepositoryProvider).requestList(),
                    child: tabsAsync.when(
                      data: (tabs) => _buildList(tabs, macOnline),
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('加载失败：$e',
                              style: TextStyle(color: t.textMuted)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (presence == MacPresence.offline) _OfflineMask(onRetry: _onRetry),
          ],
        ),
      ),
    );
  }

  String? _formatConnectionStatus(WsConnectionState? s) {
    switch (s) {
      case WsConnectionState.connecting:
        return '连接中…';
      case WsConnectionState.reconnecting:
        return '重连中…';
      case WsConnectionState.disconnected:
        return '已断开';
      case WsConnectionState.connected:
      case null:
        return null;
    }
  }

  Future<void> _onRetry() async {
    await ref.read(tabRepositoryProvider).requestList();
  }

  Widget _buildList(List<TabInfo> tabs, bool macOnline) {
    if (tabs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('暂无会话\n下拉刷新或在 Mac 端创建',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.tokens.textMuted)),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: tabs.length,
      itemBuilder: (_, i) => _TabCard(
        tab: tabs[i],
        emphasize: i == 0,
        clickable: macOnline,
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final bool macOnline;
  final String? connectionStatus;
  final int count;
  const _Header({
    required this.macOnline,
    required this.connectionStatus,
    required this.count,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态药丸
          Container(
            padding:
                const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: BoxDecoration(
              color: t.bgInset,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: t.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: macOnline ? t.success : t.textFaint,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.memory_rounded,
                      size: 14,
                      color: macOnline
                          ? const Color(0xFF001019)
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  macOnline ? 'Mac 在线' : (connectionStatus ?? 'Mac 离线'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('会话',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: t.text,
                    height: 1,
                    letterSpacing: -0.7,
                  )),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.textFaint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Spacer(),
              _CircleAction(
                icon: Icons.refresh_rounded,
                onTap: () => ref.read(tabRepositoryProvider).requestList(),
              ),
              const SizedBox(width: 6),
              _CircleAction(
                icon: Icons.settings_rounded,
                onTap: () => context.push(AppRoutes.settings),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: t.bgInset,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 14, color: t.textMuted),
      ),
    );
  }
}

class _TabCard extends StatelessWidget {
  final TabInfo tab;
  final bool emphasize;
  final bool clickable;
  const _TabCard({
    required this.tab,
    required this.emphasize,
    required this.clickable,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final running = tab.claudeStatus == ClaudeStatus.running;
    final errored = tab.claudeStatus == ClaudeStatus.error || tab.errorState;

    final card = Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.bgElev,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.line),
            boxShadow: emphasize
                ? [
                    BoxShadow(
                      color: t.accent.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                      spreadRadius: -10,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PulseDot(
                    color: running
                        ? t.success
                        : errored
                            ? t.danger
                            : t.textFaint,
                    size: 8,
                    pulse: running && emphasize,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
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
                  if (tab.pendingToolUse) _ToolBadge(),
                  if (tab.unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    _UnreadBadge(count: tab.unreadCount),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if ((tab.lastPreview ?? '').isNotEmpty)
                Text(
                  tab.lastPreview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: errored ? t.danger : t.textMuted,
                    fontFamily: errored ? 'monospace' : null,
                  ),
                ),
              const SizedBox(height: 8),
              DefaultTextStyle(
                style: TextStyle(fontSize: 11, color: t.textFaint),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 12, color: t.textFaint),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _shortenPath(tab.folder),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('·'),
                    const SizedBox(width: 6),
                    Text(_relativeTime(tab.lastActivityAt)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // leading rail
        if (running)
          Positioned(
            left: 0,
            top: 14,
            bottom: 24,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );

    return Opacity(
      opacity: clickable ? 1 : 0.5,
      child: GestureDetector(
        onTap: clickable
            ? () => context.push(
                  '${AppRoutes.chat}/${tab.id}',
                  extra: {'name': tab.name},
                )
            : null,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }

  String _shortenPath(String p) {
    if (p.length <= 28) return p;
    final parts = p.split('/');
    if (parts.length <= 3) return p;
    return '${parts.first}/…/${parts.sublist(parts.length - 2).join('/')}';
  }

  String _relativeTime(DateTime? t) {
    if (t == null) return '—';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return DateFormat('M/d').format(t);
  }
}

class _ToolBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: t.warn.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: t.warn, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('待批准',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: t.warn,
              )),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: t.accentFg,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _OfflineMask extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _OfflineMask({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Positioned.fill(
      child: Container(
        color: t.bg.withValues(alpha: 0.85),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 56, color: t.textMuted),
                const SizedBox(height: 16),
                Text('Mac 离线',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    )),
                const SizedBox(height: 8),
                Text(
                  '请确保 cc-anywhere 已在 Mac 上启动',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
