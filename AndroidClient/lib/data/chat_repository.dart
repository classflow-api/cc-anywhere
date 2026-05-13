import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/protocol_message.dart';
import 'image_upload_service.dart';
import 'logger.dart';
import 'tab_repository.dart';
import 'ws_client.dart';

/// 单个 Tab 的消息列表（已去重 + 排序）
class TabChatState {
  final String tabId;
  final List<Message> messages;
  final bool loadingMore;
  final bool hasMore;
  final String? lastError;

  const TabChatState({
    required this.tabId,
    required this.messages,
    this.loadingMore = false,
    this.hasMore = true,
    this.lastError,
  });

  TabChatState copyWith({
    List<Message>? messages,
    bool? loadingMore,
    bool? hasMore,
    String? lastError,
  }) =>
      TabChatState(
        tabId: tabId,
        messages: messages ?? this.messages,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        lastError: lastError,
      );
}

class ChatRepository {
  ChatRepository(this._ws, this._tabs, this._log, this._uploadService) {
    _sub = _ws.inbound.listen(_onInbound);
  }

  final WsClient _ws;
  final TabRepository _tabs;
  final AppLogger _log;
  final ImageUploadService _uploadService;
  final _uuid = const Uuid();

  // tabId -> state
  final Map<String, TabChatState> _state = {};
  final Map<String, StreamController<TabChatState>> _ctrls = {};

  // tabId -> uuid set（O(1) 去重）
  final Map<String, Set<String>> _uuidIndex = {};

  /// 正在打开的 tabId（用于未读累计判断）
  String? _activeTabId;

  void setActiveTab(String? tabId) {
    if (_activeTabId == tabId) return;
    _activeTabId = tabId;
    if (tabId != null) _tabs.markRead(tabId);
  }

  Stream<TabChatState> watch(String tabId) {
    final c = _ctrls.putIfAbsent(
      tabId,
      () => StreamController<TabChatState>.broadcast(),
    );
    // 提供初值
    Future<void>.microtask(() {
      final s = _state[tabId];
      if (s != null) c.add(s);
    });
    return c.stream;
  }

  TabChatState? snapshot(String tabId) => _state[tabId];

  Future<void> loadHistory(String tabId, {DateTime? before, int limit = 50}) async {
    final cur = _state[tabId] ?? TabChatState(tabId: tabId, messages: const []);
    _update(tabId, cur.copyWith(loadingMore: true, lastError: null));
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.msgHistoryRequest,
        id: _uuid.v4(),
        data: {
          'tab_id': tabId,
          'limit': limit,
          if (before != null) 'before': before.toIso8601String(),
        },
      ));
    } catch (e) {
      _log.warn('Chat', 'loadHistory failed: $e');
      _update(tabId, cur.copyWith(loadingMore: false, lastError: '$e'));
    }
  }

  Future<void> sendText(String tabId, String text) async {
    // 本地 echo（pending）
    final localUuid = 'local-${_uuid.v4()}';
    final pending = Message(
      uuid: localUuid,
      role: MessageRole.user,
      kind: MessageKind.text,
      timestamp: DateTime.now(),
      text: text,
      isLocalPending: true,
    );
    _mergeOne(tabId, pending);

    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.inputText,
        id: _uuid.v4(),
        data: {'tab_id': tabId, 'text': text},
      ));
    } catch (e) {
      _log.warn('Chat', 'sendText failed: $e');
      // 标记为失败
      _replaceByUuid(tabId, localUuid, pending.copyWith(
        isLocalPending: false,
        sendFailed: true,
      ));
      rethrow;
    }
  }

  /// 发送一组图片 + 可选文字（场景 2：发送图片）。
  ///
  /// 行为：
  /// 1. 每张图片先在本地消息流中以 pending attachment 卡片形式 echo（带进度条）
  /// 2. 串行依次 `image.upload.begin` → POST → Server 自动 forward `input.image` 给 Mac
  /// 3. 所有图片上传完成后，如果 [text] 非空再发 `input.text`
  ///
  /// 任一图片失败：标记该卡 sendFailed + uploadError，继续后续；最后若 text 已成功就发 text，
  /// 失败的图片由用户后续手动重试/删除。
  Future<void> sendTextWithImages({
    required String tabId,
    required String text,
    required List<File> images,
  }) async {
    // 1. 创建本地 attachment pending 卡
    final pendingUuids = <String>[];
    for (final file in images) {
      final uuid = 'local-${_uuid.v4()}';
      pendingUuids.add(uuid);
      int? sizeBytes;
      try {
        sizeBytes = await file.length();
      } catch (_) {/* 忽略 */}
      _mergeOne(
        tabId,
        Message(
          uuid: uuid,
          role: MessageRole.user,
          kind: MessageKind.attachment,
          timestamp: DateTime.now(),
          attachmentFilename: file.uri.pathSegments.isEmpty
              ? 'image'
              : file.uri.pathSegments.last,
          attachmentLocalPath: file.path,
          attachmentSizeBytes: sizeBytes,
          uploadProgress: 0,
          isLocalPending: true,
        ),
      );
    }

    // 2. 串行上传
    for (var i = 0; i < images.length; i++) {
      final file = images[i];
      final localUuid = pendingUuids[i];
      try {
        await _uploadService.upload(
          tabId: tabId,
          file: file,
          onProgress: (p) => _updatePendingAttachment(
            tabId,
            localUuid,
            progress: p.clamp(0.0, 1.0),
          ),
        );
        // 上传成功：进度置为 1，等待 Server forward input.image → Mac → JSONL → msg.stream
        // 那条 msg.stream 会带正式 uuid，作为新卡片渲染；本地这条 pending 保留作为已发送 echo
        _updatePendingAttachment(
          tabId,
          localUuid,
          progress: 1.0,
          isLocalPending: false,
        );
      } catch (e) {
        _log.warn('Chat', 'image upload failed: $e');
        _updatePendingAttachment(
          tabId,
          localUuid,
          isLocalPending: false,
          sendFailed: true,
          uploadError: '$e',
        );
      }
    }

    // 3. 发文字（如果有）
    if (text.isNotEmpty) {
      await sendText(tabId, text);
    }
  }

  /// 更新某条 pending attachment 消息的上传状态（进度 / 失败 / 错误）。
  ///
  /// Message.copyWith 已支持 uploadProgress / sendFailed / uploadError / isLocalPending。
  void _updatePendingAttachment(
    String tabId,
    String uuid, {
    double? progress,
    bool? isLocalPending,
    bool? sendFailed,
    String? uploadError,
  }) {
    final cur = _state[tabId];
    if (cur == null) return;
    final i = cur.messages.indexWhere((x) => x.uuid == uuid);
    if (i < 0) return;
    final m = cur.messages[i];
    final next = m.copyWith(
      uploadProgress: progress,
      isLocalPending: isLocalPending,
      sendFailed: sendFailed,
      uploadError: uploadError,
    );
    _replaceByUuid(tabId, uuid, next);
  }

  Future<void> approveToolUse(String tabId, String action) async {
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.toolUseApprove,
        id: _uuid.v4(),
        data: {'tab_id': tabId, 'action': action},
      ));
    } catch (e) {
      _log.warn('Chat', 'approve failed: $e');
      rethrow;
    }
  }

  void _onInbound(ProtocolMessage m) {
    switch (m.type) {
      case ProtocolType.msgStream:
        final tabId = m.data['tab_id'] as String?;
        if (tabId == null) return;
        final raws = (m.data['messages'] as List?) ?? const [];
        final parsed = <Message>[];
        for (final r in raws.whereType<Map>()) {
          parsed.addAll(Message.fromRaw(r.cast<String, dynamic>()));
        }
        _mergeMessages(tabId, parsed, prepend: false);
        // 未在当前 Tab 时累加未读
        if (tabId != _activeTabId && parsed.isNotEmpty) {
          final preview = parsed.lastWhere(
            (e) => e.kind == MessageKind.text,
            orElse: () => parsed.last,
          );
          _tabs.incrementUnread(tabId, preview: preview.text, at: preview.timestamp);
        }
        break;

      case ProtocolType.msgHistoryResponse:
        final tabId = m.data['tab_id'] as String?;
        if (tabId == null) return;
        final raws = (m.data['messages'] as List?) ?? const [];
        final hasMore = (m.data['has_more'] as bool?) ?? false;
        final parsed = <Message>[];
        for (final r in raws.whereType<Map>()) {
          parsed.addAll(Message.fromRaw(r.cast<String, dynamic>()));
        }
        _mergeMessages(tabId, parsed, prepend: true);
        final cur = _state[tabId] ??
            TabChatState(tabId: tabId, messages: const []);
        _update(tabId, cur.copyWith(loadingMore: false, hasMore: hasMore));
        break;

      case ProtocolType.msgRaw:
        final tabId = m.data['tab_id'] as String?;
        if (tabId == null) return;
        final line = (m.data['line'] as String?) ?? '';
        _mergeOne(
          tabId,
          Message(
            uuid: 'raw-${DateTime.now().microsecondsSinceEpoch}',
            role: MessageRole.unknown,
            kind: MessageKind.raw,
            timestamp: DateTime.now(),
            rawLine: line,
          ),
        );
        break;
    }
  }

  void _mergeMessages(String tabId, List<Message> items, {required bool prepend}) {
    final cur = _state[tabId] ?? TabChatState(tabId: tabId, messages: const []);
    final list = List<Message>.of(cur.messages);
    final index = _uuidIndex.putIfAbsent(tabId, () => <String>{});

    for (final m in items) {
      if (index.contains(m.uuid)) {
        final i = list.indexWhere((x) => x.uuid == m.uuid);
        if (i >= 0) list[i] = m;
      } else {
        if (prepend) {
          list.insert(0, m);
        } else {
          list.add(m);
        }
        index.add(m.uuid);
      }
    }
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _update(tabId, cur.copyWith(messages: list));
  }

  void _mergeOne(String tabId, Message m) => _mergeMessages(tabId, [m], prepend: false);

  void _replaceByUuid(String tabId, String uuid, Message replacement) {
    final cur = _state[tabId];
    if (cur == null) return;
    final list = List<Message>.of(cur.messages);
    final i = list.indexWhere((x) => x.uuid == uuid);
    if (i < 0) return;
    list[i] = replacement;
    _update(tabId, cur.copyWith(messages: list));
  }

  void _update(String tabId, TabChatState next) {
    _state[tabId] = next;
    _ctrls[tabId]?.add(next);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    for (final c in _ctrls.values) {
      await c.close();
    }
  }

  StreamSubscription<ProtocolMessage>? _sub;
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final r = ChatRepository(
    ref.read(wsClientProvider),
    ref.read(tabRepositoryProvider),
    ref.read(loggerProvider),
    ref.read(imageUploadServiceProvider),
  );
  ref.onDispose(r.dispose);
  return r;
});

final tabChatStateProvider = StreamProvider.family<TabChatState, String>(
  (ref, tabId) => ref.watch(chatRepositoryProvider).watch(tabId),
);
