import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/protocol_message.dart';
import '../models/tab.dart';
import 'logger.dart';
import 'ws_client.dart';

class TabRepository {
  TabRepository(this._ws, this._log) {
    _sub = _ws.inbound.listen(_onInbound);
  }

  final WsClient _ws;
  final AppLogger _log;
  final _uuid = const Uuid();

  final _tabs = <String, TabInfo>{};
  final _controller = StreamController<List<TabInfo>>.broadcast();
  StreamSubscription<ProtocolMessage>? _sub;

  Stream<List<TabInfo>> get tabsStream => _controller.stream;
  List<TabInfo> get current => _sortedList();

  Future<void> requestList() async {
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.tabListRequest,
        id: _uuid.v4(),
      ));
    } catch (e) {
      _log.warn('TabRepo', 'requestList failed: $e');
    }
  }

  void markRead(String tabId) {
    final t = _tabs[tabId];
    if (t == null || t.unreadCount == 0) return;
    _tabs[tabId] = t.copyWith(unreadCount: 0);
    _emit();
  }

  void incrementUnread(String tabId, {String? preview, DateTime? at}) {
    final t = _tabs[tabId];
    if (t == null) return;
    _tabs[tabId] = t.copyWith(
      unreadCount: t.unreadCount + 1,
      lastPreview: preview ?? t.lastPreview,
      lastActivityAt: at ?? DateTime.now(),
    );
    _emit();
  }

  void _onInbound(ProtocolMessage m) {
    switch (m.type) {
      case ProtocolType.tabListResponse:
      case ProtocolType.tabList:
        final raw = m.data['tabs'];
        if (raw is List) {
          _tabs.clear();
          for (final t in raw.whereType<Map>()) {
            final tab = TabInfo.fromJson(t.cast<String, dynamic>());
            _tabs[tab.id] = tab;
          }
          _emit();
        }
        break;
      case ProtocolType.tabChanged:
        final tabRaw = m.data['tab'];
        final action = (m.data['action'] as String?) ?? 'changed';
        if (tabRaw is Map) {
          final tab = TabInfo.fromJson(tabRaw.cast<String, dynamic>());
          if (action == 'removed') {
            _tabs.remove(tab.id);
          } else {
            _tabs[tab.id] = tab;
          }
          _emit();
        }
        break;
    }
  }

  void _emit() {
    _controller.add(_sortedList());
  }

  List<TabInfo> _sortedList() {
    final list = _tabs.values.toList();
    list.sort((a, b) {
      final ta = a.lastActivityAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.lastActivityAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    return list;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}

final tabRepositoryProvider = Provider<TabRepository>((ref) {
  final r = TabRepository(
    ref.read(wsClientProvider),
    ref.read(loggerProvider),
  );
  ref.onDispose(r.dispose);
  return r;
});

final tabsStreamProvider = StreamProvider<List<TabInfo>>(
  (ref) => ref.watch(tabRepositoryProvider).tabsStream,
);
