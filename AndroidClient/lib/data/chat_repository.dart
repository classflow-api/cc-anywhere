import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/protocol_message.dart';
import 'image_ref_store.dart';
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
  /// 用户发送后等待 Claude 响应中。收到 assistant 消息或 tool_use 后清零。
  final bool assistantTyping;

  const TabChatState({
    required this.tabId,
    required this.messages,
    this.loadingMore = false,
    this.hasMore = true,
    this.lastError,
    this.assistantTyping = false,
  });

  TabChatState copyWith({
    List<Message>? messages,
    bool? loadingMore,
    bool? hasMore,
    String? lastError,
    bool? assistantTyping,
  }) =>
      TabChatState(
        tabId: tabId,
        messages: messages ?? this.messages,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        lastError: lastError,
        assistantTyping: assistantTyping ?? this.assistantTyping,
      );
}

class ChatRepository {
  ChatRepository(this._ws, this._tabs, this._log, this._uploadService, this._imageRefStore) {
    _sub = _ws.inbound.listen(_onInbound);
  }

  final WsClient _ws;
  final ImageRefStore? _imageRefStore;
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
    // /clear:Claude Code 内置 slash command,会清空 session 上下文。
    // 同时清空 phone 端 UI 视图,语义对齐。
    if (text.trim() == '/clear') {
      _clearTabMessages(tabId);
    }
    // 标记 assistant 正在响应 — UI 显示"思考中..."占位,缓解长文本一次性出现的体验问题。
    _setTyping(tabId, true);
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
    // 记录待匹配文本:JSONL 回来的真实 user message(Claude 生成新 uuid)
    // 不能跟本地 echo dedup,会出现两条相同的"你好"气泡。
    _recordLocalPendingText(tabId, localUuid, text);

    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.inputText,
        id: _uuid.v4(),
        data: {'tab_id': tabId, 'text': text},
      ));
      // input.text 协议是 fire-and-forget(server 直接转发给 Mac,无 ack),
      // send 成功即视为已送达 WS 通道,清掉"发送中"状态。
      _replaceByUuid(tabId, localUuid, pending.copyWith(isLocalPending: false));
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
        final uploadId = await _uploadService.upload(
          tabId: tabId,
          file: file,
          onProgress: (p) => _updatePendingAttachment(
            tabId,
            localUuid,
            progress: p.clamp(0.0, 1.0),
          ),
        );
        // 上传成功后,把本地 attachment 卡片的 filename 升级成 "<upload_id>.<ext>",
        // 跟 Mac 端 ImageDownloader 落盘文件名形式一致,作为 dedup 统一 key —
        // 解决"同名图(iOS Screenshot.png / IMG_xxxx.jpg)连发时 dedup 命中第一条
        // 导致两张卡片指向同一张图"的端到端 bug。
        final originalName = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'image';
        // 跟 Mac 端 NSString.pathExtension 语义对齐:dotfile(如 .bashrc / .env)
        // 视为无扩展,避免两端 unifiedFilename 不一致破坏 dedup。
        // 即:`.bashrc`.lastIndexOf('.') == 0 → 不当扩展处理。
        final dot = originalName.lastIndexOf('.');
        final ext = (dot > 0 && dot < originalName.length - 1)
            ? originalName.substring(dot + 1)
            : '';
        final unifiedFilename = ext.isEmpty ? uploadId : '$uploadId.$ext';
        // 持久化 (unifiedFilename → uploadId) 映射,JSONL 来的 @<inbox-path> 解析时
        // 取 path 末段(也是 <upload_id>.<ext>),直接查到 uploadId 请求 download URL。
        await _imageRefStore?.put(unifiedFilename, uploadId);
        // 升级本地 attachment 的 filename + 清 pending
        final cur = _state[tabId];
        if (cur != null) {
          final i = cur.messages.indexWhere((x) => x.uuid == localUuid);
          if (i >= 0) {
            final m = cur.messages[i];
            final list = List<Message>.of(cur.messages);
            list[i] = Message(
              uuid: m.uuid,
              role: m.role,
              kind: m.kind,
              timestamp: m.timestamp,
              attachmentFilename: unifiedFilename,
              attachmentLocalPath: m.attachmentLocalPath,
              attachmentRemoteUrl: m.attachmentRemoteUrl,
              attachmentSizeBytes: m.attachmentSizeBytes,
              uploadProgress: 1.0,
              isLocalPending: false,
            );
            _update(tabId, cur.copyWith(messages: list));
          }
        }
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

  /// 凭 filename 查本地映射拿 upload_id,发 image.download.url 协议请求预览 URL。
  /// 收到 image.download.url.response 后由 _onInbound 写回该 attachment 的 remoteUrl。
  Future<void> _requestImageDownloadUrl(String tabId, String msgUuid, String filename) async {
    final store = _imageRefStore;
    if (store == null) return;
    final uploadId = await store.getUploadId(filename);
    if (uploadId == null) return;
    // 记录 uploadId -> (tabId, msgUuid),收到 response 时定位
    _pendingDownloadUrl[uploadId] = (tabId: tabId, msgUuid: msgUuid);
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.imageDownloadRequest,
        id: _uuid.v4(),
        data: {'upload_id': uploadId},
      ));
    } catch (e) {
      _log.warn('Chat', 'image.download.url request failed: $e');
      _pendingDownloadUrl.remove(uploadId);
    }
  }

  // upload_id -> 等待回填 remoteUrl 的 attachment 消息位置
  final Map<String, ({String tabId, String msgUuid})> _pendingDownloadUrl = {};

  // tabId -> 最近本地 echo 的 user text,用于跟 JSONL 回来的 user message dedup。
  // 仅保留最近 1 分钟内的 pending(window 足够 cover Mac 处理 + Claude 回写 JSONL + ws forward)。
  final Map<String, List<({String localUuid, String text, DateTime at})>>
      _localPendingTexts = {};

  // 注:之前曾有 _localPendingAttachments + _record/_consumeMatchingPendingAttachment
  // 时序记录 + 消费的 dedup 路径,已被 _mergeMessages 内"扫 list 鲁棒版"取代(需求 #31),
  // 旧路径已彻底移除,避免 dead code。

  void _recordLocalPendingText(String tabId, String localUuid, String text) {
    final list = _localPendingTexts.putIfAbsent(tabId, () => []);
    final now = DateTime.now();
    // 顺便清理过期
    list.removeWhere((e) => now.difference(e.at).inSeconds > 60);
    list.add((localUuid: localUuid, text: text, at: now));
  }

  /// 在 tabId 的 pending 列表中找一条匹配 text 的,consume(返回 localUuid 并移除)。
  String? _consumeMatchingPendingText(String tabId, String text) {
    final list = _localPendingTexts[tabId];
    if (list == null || list.isEmpty) return null;
    final now = DateTime.now();
    // 清理过期
    list.removeWhere((e) => now.difference(e.at).inSeconds > 60);
    final i = list.indexWhere((e) => e.text == text);
    if (i < 0) return null;
    final found = list[i];
    list.removeAt(i);
    return found.localUuid;
  }

  void _onInbound(ProtocolMessage m) {
    switch (m.type) {
      case ProtocolType.imageDownloadResponse:
        final uploadId = m.data['upload_id'] as String?;
        final url = m.data['image_url'] as String?;
        if (uploadId == null) return;
        final pending = _pendingDownloadUrl.remove(uploadId);
        if (pending == null) return;
        final cur = _state[pending.tabId];
        if (cur == null) return;
        final list = List<Message>.of(cur.messages);
        final i = list.indexWhere((x) => x.uuid == pending.msgUuid);
        if (i < 0) return;
        final orig = list[i];
        // url 为空 → server 上图片已过期(超出 fetchedTTL),标 uploadError 让 UI 显示"已过期"
        if (url == null || url.isEmpty) {
          list[i] = orig.copyWith(uploadError: '图片已过期,无法预览');
        } else {
          list[i] = Message(
            uuid: orig.uuid,
            role: orig.role,
            kind: orig.kind,
            timestamp: orig.timestamp,
            attachmentFilename: orig.attachmentFilename,
            attachmentLocalPath: orig.attachmentLocalPath,
            attachmentRemoteUrl: url,
            attachmentSizeBytes: orig.attachmentSizeBytes,
          );
        }
        _update(pending.tabId, cur.copyWith(messages: list));
        break;

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
      // dedup:JSONL 回来的 user text 跟本地 echo 是同一条用户消息 — Claude 生成的 uuid 跟本地 'local-xxx' 不同,
      // 不去重会出现两条相同蓝色气泡。匹配上 → 直接用 server message 替换本地这条。
      if (m.role == MessageRole.user &&
          m.kind == MessageKind.text &&
          (m.text?.isNotEmpty ?? false)) {
        final localUuid = _consumeMatchingPendingText(tabId, m.text!);
        if (localUuid != null) {
          final li = list.indexWhere((x) => x.uuid == localUuid);
          if (li >= 0) {
            list[li] = m;
            index.remove(localUuid);
            index.add(m.uuid);
            continue;
          }
        }
      }
      // attachment dedup(更鲁棒版本): 不依赖 _localPendingAttachments 记录的时序,
      // 直接扫 list 是否已存在 uuid 以 'local-' 开头 + 同 filename 的 user attachment。
      // 若有,把它的 uuid 升级为 server m.uuid,保留 localPath 已有原图预览。
      if (m.role == MessageRole.user &&
          m.kind == MessageKind.attachment &&
          (m.attachmentFilename?.isNotEmpty ?? false)) {
        final li = list.indexWhere((x) =>
            x.uuid.startsWith('local-') &&
            x.kind == MessageKind.attachment &&
            x.role == MessageRole.user &&
            x.attachmentFilename == m.attachmentFilename);
        if (li >= 0) {
          final local = list[li];
          list[li] = Message(
            uuid: m.uuid,
            role: m.role,
            kind: m.kind,
            timestamp: m.timestamp,
            attachmentFilename: m.attachmentFilename,
            attachmentLocalPath: local.attachmentLocalPath ?? m.attachmentLocalPath,
            attachmentRemoteUrl: m.attachmentRemoteUrl ?? local.attachmentRemoteUrl,
            attachmentSizeBytes: local.attachmentSizeBytes,
          );
          index.remove(local.uuid);
          index.add(m.uuid);
          continue;
        }
      }
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

    // Claude JSONL 中 tool_use 行不带 status,默认渲染为 pending;
    // tool_result 行(同 tool_use_id)表示工具已执行。
    // 扫描所有 tool_result,把对应 tool_use 卡片的 status 标记为 executed,
    // 避免手机端永远卡在"待批准"。
    for (final r in list) {
      if (r.kind == MessageKind.toolResult && r.toolUseRefId != null) {
        for (var i = 0; i < list.length; i++) {
          final u = list[i];
          if (u.kind == MessageKind.toolUse &&
              u.toolUseId == r.toolUseRefId &&
              u.toolStatus != ToolUseStatus.executed) {
            list[i] = u.copyWith(toolStatus: ToolUseStatus.executed);
          }
        }
      }
    }

    // 扫描新增的 attachment(by inbox-path)且无 remoteUrl 的卡片,
    // 异步触发 image.download.url 请求获取预览 URL。
    for (final m in items) {
      if (m.kind == MessageKind.attachment &&
          m.attachmentRemoteUrl == null &&
          m.attachmentFilename != null &&
          m.attachmentLocalPath != null &&
          m.attachmentLocalPath!.contains('cc-anywhere/inbox/')) {
        _requestImageDownloadUrl(tabId, m.uuid, m.attachmentFilename!);
      }
    }

    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _update(tabId, cur.copyWith(messages: list));
    // 收到任意 assistant 消息(text/thinking/toolUse/toolResult)→ 关闭"思考中"占位。
    // 走 _setTyping 以触发 timer 清理,避免 orphan timer。
    final hasAssistant = items.any((m) =>
        m.role == MessageRole.assistant ||
        m.kind == MessageKind.toolUse ||
        m.kind == MessageKind.toolResult ||
        m.kind == MessageKind.thinking);
    if (hasAssistant) {
      _setTyping(tabId, false);
    }
  }

  void _mergeOne(String tabId, Message m) => _mergeMessages(tabId, [m], prepend: false);

  /// 60s 超时兜底:Mac 崩/网断/Claude 异常导致永远收不到 assistant 消息时,
  /// 避免手机端"思考中..."永挂。即使触发,后续收到真 assistant 消息也会自然 _setTyping(false)。
  final Map<String, Timer> _typingTimers = {};

  void _setTyping(String tabId, bool typing) {
    final cur = _state[tabId] ?? TabChatState(tabId: tabId, messages: const []);
    // 取消上一个 timer
    _typingTimers.remove(tabId)?.cancel();
    if (typing) {
      _typingTimers[tabId] = Timer(const Duration(seconds: 60), () {
        _setTyping(tabId, false);
      });
    }
    if (cur.assistantTyping == typing) return;
    _update(tabId, cur.copyWith(assistantTyping: typing));
  }

  /// 清空指定 tab 的本地消息视图(/clear slash command 触发)。
  /// 同时清 typing — /clear 后 Claude 不会有 assistant 消息回放(被 message.dart 过滤),
  /// 不清的话"思考中..."永挂直到 60s 超时。
  void _clearTabMessages(String tabId) {
    final cur = _state[tabId];
    if (cur == null) return;
    _uuidIndex[tabId]?.clear();
    _localPendingTexts[tabId]?.clear();
    // 清掉该 tab 所有 pending download URL 请求映射 — /clear 之后这些响应到来也无意义。
    _pendingDownloadUrl.removeWhere((_, v) => v.tabId == tabId);
    _typingTimers.remove(tabId)?.cancel();
    _update(tabId, cur.copyWith(messages: const [], hasMore: false, assistantTyping: false));
  }

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
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _pendingDownloadUrl.clear();
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
    // imageRefStore 是 FutureProvider — provider 在 App 启动时 prefetch,
    // 取 valueOrNull 避免阻塞 chat 初始化(首次启动若还没 ready,本次会跳过记映射,无害)
    ref.read(imageRefStoreProvider).valueOrNull,
  );
  ref.onDispose(r.dispose);
  return r;
});

final tabChatStateProvider = StreamProvider.family<TabChatState, String>(
  (ref, tabId) => ref.watch(chatRepositoryProvider).watch(tabId),
);
