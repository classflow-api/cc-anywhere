import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/protocol_message.dart';
import 'logger.dart';
import 'ws_client.dart';

class SlashCommand {
  final String name;
  final String description;
  final String source; // "builtin" | "user" | "project" | "plugin:<x>"
  const SlashCommand({
    required this.name,
    required this.description,
    required this.source,
  });

  factory SlashCommand.fromJson(Map<String, dynamic> j) => SlashCommand(
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        source: j['source'] as String? ?? '',
      );
}

/// 维护 (tabId -> [SlashCommand]) 缓存,接收 Mac 端的 slash.list.response,
/// UI 可主动调 [requestList] 让 Mac 重新扫一次。
class SlashCommandRepository {
  SlashCommandRepository(this._ws, this._log) {
    _sub = _ws.inbound.listen(_onInbound);
  }

  final WsClient _ws;
  final AppLogger _log;
  final _uuid = const Uuid();
  StreamSubscription<ProtocolMessage>? _sub;

  // tabId -> commands
  final Map<String, List<SlashCommand>> _cache = {};
  final _controller = StreamController<MapEntry<String, List<SlashCommand>>>.broadcast();

  Stream<MapEntry<String, List<SlashCommand>>> get changes => _controller.stream;
  List<SlashCommand> commands(String tabId) =>
      List<SlashCommand>.unmodifiable(_cache[tabId] ?? const []);

  Future<void> requestList(String tabId) async {
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.slashListRequest,
        id: _uuid.v4(),
        data: {'tab_id': tabId},
      ));
    } catch (e) {
      _log.warn('SlashRepo', 'requestList failed: $e');
    }
  }

  void _onInbound(ProtocolMessage m) {
    if (m.type != ProtocolType.slashListResponse) return;
    final tabId = m.data['tab_id'] as String?;
    final raws = m.data['commands'] as List?;
    if (tabId == null || raws == null) return;
    final list = <SlashCommand>[];
    for (final r in raws.whereType<Map>()) {
      list.add(SlashCommand.fromJson(r.cast<String, dynamic>()));
    }
    _cache[tabId] = list;
    _controller.add(MapEntry(tabId, list));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}

final slashCommandRepositoryProvider = Provider<SlashCommandRepository>((ref) {
  final r = SlashCommandRepository(
    ref.read(wsClientProvider),
    ref.read(loggerProvider),
  );
  ref.onDispose(r.dispose);
  return r;
});
