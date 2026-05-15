import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tab_repository.dart';
import '../data/ws_client.dart';
import '../models/protocol_message.dart';
import '../models/tab.dart';

/// 单条 toast 显示时长（R-F3-002 隐含语义：3 秒后自动关闭，
/// 队列里下一条立即接上）。
const _toastDuration = Duration(seconds: 3);

/// 同时最多显示数量 —— R-F3-002：最多同时显示 3 个，超出排队等待。
const _maxConcurrent = 3;

/// 队列内单条等待 toast 上限 —— 防止后端异常导致无限堆积。
const _maxQueueLength = 30;

/// 单条 toast 数据
class _ToastItem {
  _ToastItem(this.payload, this.tabName);
  final NotificationPayload payload;
  final String? tabName;
  final String id = UniqueKey().toString();
}

/// 全局 toast 服务：监听 ws 入站 [ProtocolType.notification]，按 R-F3-002
/// 控制并发为 3，超出则队列等待。
class NotificationToastService extends ChangeNotifier {
  NotificationToastService(this._ws, this._tabs) {
    _sub = _ws.inbound.listen(_onInbound);
  }

  final WsClient _ws;
  final TabRepository _tabs;
  StreamSubscription<ProtocolMessage>? _sub;

  /// 排队等待中的消息
  final Queue<_ToastItem> _queue = Queue<_ToastItem>();

  /// 当前正在显示的消息（按入显示顺序，最多 [_maxConcurrent] 条）
  final List<_ToastItem> _visible = [];

  /// timer 表：dismiss 单条 toast
  final Map<String, Timer> _timers = {};

  /// 当前显示中的副本（不可变快照，供 UI 消费）
  List<_ToastItem> get visible => List.unmodifiable(_visible);

  void _onInbound(ProtocolMessage m) {
    if (m.type != ProtocolType.notification) return;
    final p = NotificationPayload.tryFrom(m.data);
    if (p == null) return;
    // 反向查 tab 名称（找不到时退化为空，模板会用 tabId 截短代替）
    String? tabName;
    final tab = _tabs.current.where((TabInfo t) => t.id == p.tabId);
    if (tab.isNotEmpty) tabName = tab.first.name;
    _enqueue(_ToastItem(p, tabName));
  }

  void _enqueue(_ToastItem item) {
    if (_visible.length < _maxConcurrent) {
      _show(item);
    } else {
      // 防止异常堆积
      if (_queue.length >= _maxQueueLength) {
        _queue.removeFirst();
      }
      _queue.add(item);
    }
  }

  void _show(_ToastItem item) {
    _visible.add(item);
    _timers[item.id] = Timer(_toastDuration, () => _dismiss(item.id));
    notifyListeners();
  }

  void _dismiss(String id) {
    _timers.remove(id)?.cancel();
    final idx = _visible.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    _visible.removeAt(idx);
    // 从队列拉下一条
    if (_queue.isNotEmpty) {
      _show(_queue.removeFirst());
    } else {
      notifyListeners();
    }
  }

  /// 手动关闭某条 toast（暴露给 UI 点击关闭按钮场景）
  void dismiss(String id) => _dismiss(id);

  @override
  void dispose() {
    _sub?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _queue.clear();
    _visible.clear();
    super.dispose();
  }
}

final notificationToastServiceProvider =
    ChangeNotifierProvider<NotificationToastService>((ref) {
  final s = NotificationToastService(
    ref.read(wsClientProvider),
    ref.read(tabRepositoryProvider),
  );
  ref.onDispose(s.dispose);
  return s;
});

/// 顶部 Overlay toast 容器 —— 应作为 [MaterialApp.builder] 中
/// `Stack` 顶层一员包裹整棵路由树（参见 [NotificationToastHost]）。
class NotificationToast extends ConsumerWidget {
  const NotificationToast({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(notificationToastServiceProvider);
    final items = service.visible;
    if (items.isEmpty) return const SizedBox.shrink();
    final safeTop = MediaQuery.of(context).padding.top;
    return Positioned(
      top: safeTop + 8,
      left: 12,
      right: 12,
      child: IgnorePointer(
        ignoring: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _ToastCard(
                  item: item,
                  onClose: () => service.dismiss(item.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 包裹任意 child + 顶部叠加 toast Overlay 的便捷 Wrapper。
/// 适合直接放进 `MaterialApp.builder` 的返回值里。
///
/// 实现说明:外层 Stack 第一个 child 是页面树本身,第二个 child 是
/// [NotificationToast]。toast 内部用 [Positioned] 限定在顶部安全区域,
/// 仅在 toast 渲染区接收点击;其他区域 Stack 不参与 hit-test,因此
/// 下层 UI 不会被无形遮罩拦截。
class NotificationToastHost extends StatelessWidget {
  const NotificationToastHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const NotificationToast(),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.item, required this.onClose});
  final _ToastItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = _toastColors(item.payload.notificationType,
        Theme.of(context).brightness == Brightness.dark);
    // R-F3-003: 文本格式 [Tab {tab_name}] {title}: {message}
    final tabLabel = item.tabName?.trim().isNotEmpty == true
        ? item.tabName!
        : _shortId(item.payload.tabId);
    final title = item.payload.title.trim();
    final message = item.payload.message.trim();
    final composed = StringBuffer('[Tab ')
      ..write(tabLabel)
      ..write('] ');
    if (title.isNotEmpty) {
      composed.write(title);
      if (message.isNotEmpty) composed.write(': ');
    }
    composed.write(message);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4, right: 10),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.dot,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Text(
                composed.toString(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: colors.fg,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                splashRadius: 14,
                tooltip: '关闭',
                icon: Icon(Icons.close, color: colors.fg.withValues(alpha: 0.7)),
                onPressed: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortId(String id) {
    if (id.length <= 8) return id;
    return id.substring(0, 8);
  }
}

/// Toast 配色，R-F3-003：idle 灰 / permission_prompt 黄 / error 红。
class _ToastColors {
  const _ToastColors({
    required this.bg,
    required this.border,
    required this.dot,
    required this.fg,
  });
  final Color bg;
  final Color border;
  final Color dot;
  final Color fg;
}

_ToastColors _toastColors(String type, bool dark) {
  switch (type) {
    case 'error':
      return _ToastColors(
        bg: dark ? const Color(0xFF3B1F22) : const Color(0xFFFDECEC),
        border: const Color(0xFFE5484D),
        dot: const Color(0xFFE5484D),
        fg: dark ? const Color(0xFFFFD9DB) : const Color(0xFF7A1F22),
      );
    case 'permission_prompt':
      return _ToastColors(
        bg: dark ? const Color(0xFF3A2F12) : const Color(0xFFFFF5D6),
        border: const Color(0xFFE0A53A),
        dot: const Color(0xFFE0A53A),
        fg: dark ? const Color(0xFFFFE6A8) : const Color(0xFF6B4A0B),
      );
    case 'idle':
    default:
      return _ToastColors(
        bg: dark ? const Color(0xFF2A2A2A) : const Color(0xFFECECEC),
        border: const Color(0xFF8C8C8C),
        dot: const Color(0xFF8C8C8C),
        fg: dark ? const Color(0xFFD8D8D8) : const Color(0xFF3A3A3A),
      );
  }
}
