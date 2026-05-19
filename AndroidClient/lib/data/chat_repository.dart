import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../features/chat/widgets/sub_agent_folded_block.dart';
import '../models/message.dart';
import '../models/protocol_message.dart';
import '../models/todo_item.dart';
import '../services/dedup_service.dart';
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
  /// R-T1-001 / R-T1-002 / R-T1-005：主 session（isSidechain=false）最新一次
  /// TodoWrite 的 todos 快照。每次 TodoWrite 覆盖式更新，按 tabId 隔离。
  /// 空列表 = 当前 Tab 无任务清单（panel 隐藏，R-T1-008）。
  final List<TodoItem> todos;

  const TabChatState({
    required this.tabId,
    required this.messages,
    this.loadingMore = false,
    this.hasMore = true,
    this.lastError,
    this.assistantTyping = false,
    this.todos = const [],
  });

  TabChatState copyWith({
    List<Message>? messages,
    bool? loadingMore,
    bool? hasMore,
    String? lastError,
    bool? assistantTyping,
    List<TodoItem>? todos,
  }) =>
      TabChatState(
        tabId: tabId,
        messages: messages ?? this.messages,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        lastError: lastError,
        assistantTyping: assistantTyping ?? this.assistantTyping,
        todos: todos ?? this.todos,
      );
}

class ChatRepository {
  ChatRepository(this._ws, this._tabs, this._log, this._uploadService,
      this._imageRefStore, this._dedup) {
    _sub = _ws.inbound.listen(_onInbound);
    // 预热 dedup 缓存,让 _mergeMessages 中的同步 dedup 调用走快路径(in-memory)。
    _dedup?.prewarm();
  }

  final WsClient _ws;
  final ImageRefStore? _imageRefStore;
  final TabRepository _tabs;
  final AppLogger _log;
  final ImageUploadService _uploadService;
  /// hook 实时通道 + JSONL 旁观通道按 tool_use_id 双端去重(F5)。
  /// 启动前若 SharedPreferences 还未 ready 取 null,此时仅靠 in-memory uuid 索引兜底。
  final DedupService? _dedup;
  final _uuid = const Uuid();

  // tabId -> state
  final Map<String, TabChatState> _state = {};
  final Map<String, StreamController<TabChatState>> _ctrls = {};

  // tabId -> uuid set（O(1) 去重）
  final Map<String, Set<String>> _uuidIndex = {};

  // L4 子 agent 聚合（R-F3-001 ~ R-F3-004）
  //
  // _subAgentBlocks：tabId → key → block，key 优先 parentToolUseId（已匹配到主流
  //                 Task tool_use 时），否则用 agentId（孤儿模式：mac 端 promptHash
  //                 反查失败或子先到时）。
  // _pendingSidechainBuffer：tabId → key → 已到达但父尚未到的 sidechain JSONL
  //                 records；超时后转孤儿（直接以 agentId 为 key 建块展示，不再
  //                 等父，R-F3-003 不回溯重组）。
  // _bufferTimeouts：每个等待中的 key 一个 timer；超时立即把 buffered 转 block 落地。
  // _bufferTtlSeconds：标记 key 在哪个超时档位上。
  // _subAgentBlockKeys：tabId → 已创建过 SubAgentFoldedBlock 占位 Message 的 key
  //                 集合（避免重复插入）。
  // _subAgentTimestamp：每个 key 首条到达时间（用作 placeholder Message 的 timestamp，
  //                 让折叠块按真实时间线插入）。
  // dedup：sidechain message uuid 集合用于 R-F3-004（同 uuid 重复到达只渲染一次，
  //       JSONL 通道 + 历史回放可能撞 uuid）。
  final Map<String, Map<String, SubAgentBlock>> _subAgentBlocks = {};
  final Map<String, Map<String, List<Map<String, dynamic>>>>
      _pendingSidechainBuffer = {};
  final Map<String, Map<String, Timer>> _bufferTimeouts = {};
  final Map<String, Set<String>> _subAgentBlockKeys = {};
  final Map<String, Map<String, DateTime>> _subAgentTimestamps = {};
  final Map<String, Set<String>> _sidechainUuidIndex = {};

  /// 实时通道 5 秒；历史回放 30 秒（R-F8-002）— 历史批量到达时 race 窗口更大。
  static const Duration _bufferTimeoutRealtime = Duration(seconds: 5);
  static const Duration _bufferTimeoutHistory = Duration(seconds: 30);

  /// 暴露给 message_card_list lookup：根据 placeholder Message 的 uuid 还原块。
  /// uuid 形如 `subagent-{tabId}-{key}`。
  SubAgentBlock? lookupSubAgentBlock(String tabId, String key) =>
      _subAgentBlocks[tabId]?[key];

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

  /// hook 实时通道按 tool_use_id 去重。
  ///
  /// `ask.question.pending` / `tool.progress.pre` / `tool.progress.post` 三类协议
  /// 都携带 `tool_use_id`,经由 server 转发,phone 端在分发前先查 DedupService 决定是否处理。
  /// 与 JSONL 旁观通道(_mergeMessages 中 MessageKind.toolUse 路径)使用同一份 ttl 缓存,
  /// 实现 hook + JSONL 双通道去重。
  ///
  /// 返回 true 表示首次见到、应继续处理；false 表示已处理过应跳过。
  /// 异常路径(没有 tool_use_id / DedupService 未就绪)默认放行,避免误吞消息。
  Future<bool> _checkHookDedup(ProtocolMessage m) async {
    final dedup = _dedup;
    if (dedup == null) return true;
    final toolUseId = m.data['tool_use_id'];
    if (toolUseId is! String || toolUseId.isEmpty) return true;
    final shouldHandle = await dedup.checkAndMark(toolUseId);
    if (!shouldHandle) {
      _log.debug('Chat', 'dedup skip hook ${m.type} tool_use_id=$toolUseId');
    }
    return shouldHandle;
  }

  void _onInbound(ProtocolMessage m) {
    // hook 实时桥接通道:统一在分发入口对 ask/progress 系列消息做 tool_use_id 去重。
    // 这三类协议的具体渲染逻辑由后续 T13/T14/T15 子 agent 合入,此处仅守门。
    switch (m.type) {
      case 'ask.question.pending':
      case 'tool.progress.pre':
      case 'tool.progress.post':
        // fire-and-forget:dedup 决策不阻塞主流程,后续渲染逻辑应使用 _checkHookDedup
        // 在自己的处理路径中显式 await 决策。这里先记日志,确保命中可观测。
        _checkHookDedup(m).then((shouldHandle) {
          if (!shouldHandle) {
            _log.info('Chat', 'hook ${m.type} deduped (already handled)');
          }
        });
        break;
    }
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
        // L4：先经子 agent 聚合预处理 — sidechain 记录被吸入折叠块、Task
        // tool_use/tool_result 旁路在主流保留同时建/收尾折叠块。返回过滤后仍
        // 要进主流的 raws + 新增的 SubAgentFoldedBlock 占位 Message。
        final preprocessed = _preprocessSubAgent(
          tabId: tabId,
          raws: raws.whereType<Map>().map((e) => e.cast<String, dynamic>()),
          isHistory: false,
        );
        final parsed = <Message>[];
        for (final r in preprocessed.passthroughRaws) {
          parsed.addAll(Message.fromRaw(r));
        }
        parsed.addAll(preprocessed.newPlaceholders);
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
        // 历史回放：buffer 超时延长到 30s（R-F8-002），但同样走聚合路径。
        final preprocessed = _preprocessSubAgent(
          tabId: tabId,
          raws: raws.whereType<Map>().map((e) => e.cast<String, dynamic>()),
          isHistory: true,
        );
        final parsed = <Message>[];
        for (final r in preprocessed.passthroughRaws) {
          parsed.addAll(Message.fromRaw(r));
        }
        parsed.addAll(preprocessed.newPlaceholders);
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

  /// L4 子 agent 聚合预处理（R-F3-001 ~ R-F3-004）。
  ///
  /// 接收 msg.stream / msg.history.response 一批 JSONL raw record（每条是个 Map），
  /// 按 isSidechain 字段分流：
  ///  - isSidechain=true：吸入对应 parentToolUseId/agentId 块的 children，不进主流
  ///  - isSidechain=false 且 message.content 含 type=tool_use && name=Task：
  ///       同时建/更新 SubAgentBlock（key=tool_use.id），并保留原 raw 进主流（用户
  ///       照常看到 Task 工具卡）
  ///  - isSidechain=false 且 message.content 含 type=tool_result 且 tool_use_id
  ///       命中已存在的 SubAgentBlock：写入 finalResult，主流仍保留（dedup 由
  ///       _mergeMessages 处理）
  ///
  /// 返回需要走主流 Message.fromRaw 的 raws 列表 + 本批次首次创建的折叠块
  /// placeholder Message（要插入主消息流让用户看到块）。
  ({List<Map<String, dynamic>> passthroughRaws, List<Message> newPlaceholders})
      _preprocessSubAgent({
    required String tabId,
    required Iterable<Map<String, dynamic>> raws,
    required bool isHistory,
  }) {
    final passthrough = <Map<String, dynamic>>[];
    final newPlaceholders = <Message>[];
    final blocks = _subAgentBlocks.putIfAbsent(tabId, () => {});
    final pending = _pendingSidechainBuffer.putIfAbsent(tabId, () => {});
    final placeholderKeys = _subAgentBlockKeys.putIfAbsent(tabId, () => {});
    final timestamps = _subAgentTimestamps.putIfAbsent(tabId, () => {});
    final sidechainUuids = _sidechainUuidIndex.putIfAbsent(tabId, () => {});

    // 第二轮 review 🟡-2:历史回放路径下 batch 收集 TodoWrite,
    // 一批 N 条只在循环结束时 emit 一次（避免 panel 闪烁与无谓 rebuild）。
    // 实时路径仍每条立即 emit（保证 mac 上 Claude 实时更新时手机也实时反映）。
    List<TodoItem>? batchedTodos;

    for (final raw in raws) {
      final isSidechain = (raw['isSidechain'] as bool?) ?? false;
      final uuid = raw['uuid'] as String?;

      // R-F3-004 dedup：sidechain 记录按 uuid 去重（同一 uuid 重复到达只处理一次）。
      // 主流非 sidechain 仍走原 _mergeMessages 的 uuid 去重路径，这里不重复管。
      if (isSidechain && uuid != null && sidechainUuids.contains(uuid)) {
        continue;
      }

      if (isSidechain) {
        if (uuid != null) sidechainUuids.add(uuid);
        // 优先 parentToolUseId；mac 端 promptHash 反查命中才注入此字段，否则
        // fallback 用 agentId（孤儿模式占位）。
        final parentId = raw['parent_tool_use_id'] as String?;
        final agentId = raw['agentId'] as String?;
        final key = parentId ?? agentId;
        if (key == null) {
          // 既无 parentToolUseId 又无 agentId 的 sidechain — 协议字段都缺，
          // 退化为现有体验直接进主流（R-F3 中 ⊕ "孤儿且无父" 极端兜底）。
          passthrough.add(raw);
          continue;
        }
        if (blocks.containsKey(key)) {
          blocks[key]!.children.add(raw);
        } else {
          // 父尚未到 → 暂存，启动 buffer 超时
          pending.putIfAbsent(key, () => []).add(raw);
          _scheduleBufferTimeout(
            tabId: tabId,
            key: key,
            agentId: agentId ?? key,
            isHistory: isHistory,
          );
        }
        // R-F3-001：sidechain 不进主流，避免双卡
        continue;
      }

      // 非 sidechain：探测 TodoWrite,把 todos 吸入主 panel。
      // R-T1-001 / R-T1-007：仅主 session 的 TodoWrite 进主 panel,子 agent 内
      // TodoWrite 走 sidechain 分支（已在前面 continue），永不到这里。
      //
      // 第一轮 review 🟡-2：原实现在命中后 continue 把整条 raw 丢弃,若同条
      // message.content 含 text + TodoWrite 会丢 text。改为 raw 仍进 passthrough,
      // 消音逻辑下沉到 message_card_list 渲染层（R-T1-006 在渲染层执行）。
      //
      // 第二轮 review 🟡-2：历史回放路径下 batch 收集,循环外 emit 一次,
      // 避免一次性收到 N 条历史 TodoWrite 触发 N 次 panel rebuild。
      final todoUpdate = _detectTodoWrite(raw);
      if (todoUpdate != null) {
        if (isHistory) {
          batchedTodos = todoUpdate;
        } else {
          _setTodos(tabId, todoUpdate);
        }
      }

      // 第二轮 review 🟡-2：tool_result 已被折叠块 finalResult 吸收时跳过主流，
      // 避免"主流 ToolResultCard + 折叠块内 _buildFinalResult"双重渲染。
      var absorbedByBlock = false;

      final detection = _detectTaskInRecord(raw);
      if (detection != null) {
        if (detection.kind == _TaskRecordKind.toolUse) {
          // 父 Task tool_use 到达 — 建立或回填折叠块
          final taskKey = detection.toolUseId;
          if (taskKey != null) {
            final ts = _parseRecordTs(raw);
            final summary = _truncate(detection.promptSummary ?? '', 60);
            final block = blocks.putIfAbsent(
              taskKey,
              () => SubAgentBlock(
                agentId: detection.agentId ?? taskKey,
                parentToolUseId: taskKey,
                promptSummary: summary,
              ),
            );
            // 即使已存在（罕见：先 race 由 agentId 建过孤儿块后 task 又来），
            // 字段补齐
            if (block.promptSummary.isEmpty && summary.isNotEmpty) {
              // 不能直接覆盖 final 字段，但我们没把 promptSummary 设 final，
              // 故反射式行不通；这里只 best-effort：忽略（极少触发，孤儿块仍可见）。
            }
            // 收割 pending buffer
            final waiting = pending.remove(taskKey);
            if (waiting != null) {
              block.children.addAll(waiting);
              _bufferTimeouts[tabId]?.remove(taskKey)?.cancel();
            }
            // 首次见到 — 插入主流占位 Message（按 Task tool_use 真实时间）
            if (!placeholderKeys.contains(taskKey)) {
              placeholderKeys.add(taskKey);
              timestamps[taskKey] = ts;
              newPlaceholders.add(_buildPlaceholder(tabId, taskKey, ts));
            }
          }
        } else if (detection.kind == _TaskRecordKind.toolResult) {
          // 父 session 的 Task tool_result — 收尾对应折叠块
          final refId = detection.toolUseId;
          if (refId != null && blocks.containsKey(refId)) {
            final block = blocks[refId]!;
            block.finalResult = raw;
            // R-F4-003：含 error 字段 → 失败
            block.status = detection.isError == true ? 'failed' : 'done';
            absorbedByBlock = true;  // R-F4-002 隐含语义：final 是折叠块组成部分
          }
        }
      }

      if (!absorbedByBlock) {
        passthrough.add(raw);
      }
    }

    // 第二轮 review 🟡-2:历史回放路径在循环末尾统一 emit 最后一次 todos
    if (batchedTodos != null) {
      _setTodos(tabId, batchedTodos);
    }

    return (passthroughRaws: passthrough, newPlaceholders: newPlaceholders);
  }

  /// 5s / 30s 超时后把 pending sidechain 转为孤儿块（agentId 作 key）。
  /// R-F3-002 / R-F3-003：超时孤儿展示，后续父消息再到达**不回溯重组**避免 UI 闪烁。
  void _scheduleBufferTimeout({
    required String tabId,
    required String key,
    required String agentId,
    required bool isHistory,
  }) {
    final timers = _bufferTimeouts.putIfAbsent(tabId, () => {});
    // 已有 timer 不重置 — 老 timer 计的是首条到达后的窗口，重置会让窗口被
    // 持续刷新到永远（race 中子 agent 边到边刷会饿死孤儿展示）。
    if (timers.containsKey(key)) return;
    final dur = isHistory ? _bufferTimeoutHistory : _bufferTimeoutRealtime;
    timers[key] = Timer(dur, () {
      timers.remove(key);
      final pending = _pendingSidechainBuffer[tabId]?.remove(key);
      if (pending == null || pending.isEmpty) return;
      final blocks = _subAgentBlocks.putIfAbsent(tabId, () => {});
      final placeholderKeys =
          _subAgentBlockKeys.putIfAbsent(tabId, () => {});
      // 孤儿块：用 agentId 当 key，无 parentToolUseId
      final block = blocks.putIfAbsent(
        key,
        () => SubAgentBlock(
          agentId: agentId,
          parentToolUseId: null,
          promptSummary: '',
        ),
      );
      block.children.addAll(pending);
      if (!placeholderKeys.contains(key)) {
        placeholderKeys.add(key);
        final ts = _parseRecordTs(pending.first);
        _subAgentTimestamps.putIfAbsent(tabId, () => {})[key] = ts;
        // 直接走 _mergeMessages 单条插入：buffer 超时是异步事件，没法走
        // _preprocessSubAgent 的 newPlaceholders 返回路径。
        _mergeOne(tabId, _buildPlaceholder(tabId, key, ts));
      } else {
        // 已有占位 → 仅刷新状态（_subAgentBlocks 是引用类型，widget 重 build 会
        // 自动取到新 children），但 widget 在 Stream 上是 push 的，需要主动 emit。
        final cur = _state[tabId];
        if (cur != null) _update(tabId, cur);
      }
    });
  }

  Message _buildPlaceholder(String tabId, String key, DateTime ts) => Message(
        uuid: 'subagent-$tabId-$key',
        role: MessageRole.assistant,
        kind: MessageKind.subAgentBlock,
        timestamp: ts,
      );

  DateTime _parseRecordTs(Map<String, dynamic> raw) {
    final v = raw['timestamp'] ?? raw['created_at'];
    if (v is String) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt;
    }
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return DateTime.now();
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// 解析一条非 sidechain JSONL record，查 message.content 中是否含 Task
  /// tool_use 或 tool_result，提取信息。返回 null 表示与 Task 无关。
  /// R-T1-001 ~ R-T1-011：识别 TodoWrite tool_use 的 input.todos 数组。
  /// 命中返回解析后的 todos 列表（caller 用 _setTodos 覆盖当前 Tab 的 panel 状态）；
  /// 未命中返回 null。
  ///
  /// 第一轮 review 🟡-1：input.todos 字段缺失 / 非 List 时返回 null（**不**更新 panel），
  /// 否则 TodoItem.parseList 会返回 [] 把已有的 panel 清空，与 §6 safe degradation 不符。
  /// 仅当 todos 字段存在且能成功解析出 ≥0 条有效项才更新 panel。
  List<TodoItem>? _detectTodoWrite(Map<String, dynamic> raw) {
    try {
      final inner = raw['message'];
      if (inner is! Map) return null;
      final content = inner['content'];
      if (content is! List) return null;
      for (final item in content) {
        if (item is! Map) continue;
        if (item['type'] != 'tool_use' || item['name'] != 'TodoWrite') continue;
        final input = item['input'];
        if (input is! Map) continue;
        final todosField = input['todos'];
        if (todosField is! List) return null;  // 字段缺失/非 List → safe degradation
        return TodoItem.parseList(todosField);
      }
    } catch (_) {/* 解析失败静默忽略 */}
    return null;
  }

  /// R-T1-005：同一 Tab 内连续多次 TodoWrite 仅保留最新状态（覆盖式更新）。
  void _setTodos(String tabId, List<TodoItem> todos) {
    final cur = _state[tabId] ?? TabChatState(tabId: tabId, messages: const []);
    _update(tabId, cur.copyWith(todos: todos));
  }

  _TaskRecordDetection? _detectTaskInRecord(Map<String, dynamic> raw) {
    try {
      final inner = raw['message'];
      if (inner is! Map) return null;
      final content = inner['content'];
      if (content is! List) return null;
      for (final item in content) {
        if (item is! Map) continue;
        final type = item['type'];
        if (type == 'tool_use' && item['name'] == 'Task') {
          final id = item['id'] as String?;
          String? prompt;
          final input = item['input'];
          if (input is Map) {
            final p = input['prompt'];
            if (p is String) prompt = p;
          }
          return _TaskRecordDetection(
            kind: _TaskRecordKind.toolUse,
            toolUseId: id,
            promptSummary: prompt,
            // 父 session 的 Task tool_use 没有 agentId（agentId 是 sidechain 内
            // 才有的子 agent 短 hash），此处置 null。
            agentId: null,
            isError: null,
          );
        }
        if (type == 'tool_result') {
          // 仅当 tool_use_id 命中已知子 agent 块才视作 Task tool_result。
          // 普通工具的 tool_result 也长这样，但 caller 会判断 blocks.containsKey。
          final refId = item['tool_use_id'] as String?;
          final isErr = item['is_error'] as bool?;
          return _TaskRecordDetection(
            kind: _TaskRecordKind.toolResult,
            toolUseId: refId,
            promptSummary: null,
            agentId: null,
            isError: isErr,
          );
        }
      }
    } catch (_) {/* 解析失败静默放行，主流照常 */}
    return null;
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
      // JSONL 旁观通道 tool_use 行的 dedup:hook 实时通道若已为同 tool_use_id 推送过卡片,
      // 这里跳过避免渲染两份(R-F5-001 ~ R-F5-004)。
      // 注:askUserQuestion 是 AskUserQuestion 工具的特例,kind 在 message.dart 解析时
      //   被单独标识,也按 toolUseId 去重。
      // tool_result 不做 dedup — tool_result 是 hook 通道没有的,JSONL 是唯一源。
      if ((m.kind == MessageKind.toolUse || m.kind == MessageKind.askUserQuestion) &&
          (m.toolUseId?.isNotEmpty ?? false) &&
          _dedup != null) {
        final id = m.toolUseId!;
        if (_dedup.hasHandledSync(id)) {
          // 已被 hook 通道处理,跳过 JSONL 渲染。
          continue;
        }
        // 首次见到:标记,后续 hook 或 JSONL 再来都将命中 dedup。
        _dedup.markSync(id);
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
    // L4：/clear 同步清空子 agent 折叠块 + buffer + timers，否则历史块仍残留可点开。
    _subAgentBlocks[tabId]?.clear();
    _pendingSidechainBuffer[tabId]?.clear();
    _subAgentBlockKeys[tabId]?.clear();
    _subAgentTimestamps[tabId]?.clear();
    _sidechainUuidIndex[tabId]?.clear();
    final timers = _bufferTimeouts[tabId];
    if (timers != null) {
      for (final t in timers.values) {
        t.cancel();
      }
      timers.clear();
    }
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
    // L4 子 agent buffer timers：dispose 时全部 cancel，避免 widget tree 卸载后
    // closure 仍 fire 触发 _mergeOne 撞已关闭 stream。
    for (final timers in _bufferTimeouts.values) {
      for (final t in timers.values) {
        t.cancel();
      }
    }
    _bufferTimeouts.clear();
    for (final c in _ctrls.values) {
      await c.close();
    }
  }

  StreamSubscription<ProtocolMessage>? _sub;
}

/// 内部辅助：从一条非 sidechain JSONL record 提取出的 Task 相关信息。
enum _TaskRecordKind { toolUse, toolResult }

class _TaskRecordDetection {
  final _TaskRecordKind kind;
  final String? toolUseId;
  final String? promptSummary;
  final String? agentId;
  final bool? isError;
  const _TaskRecordDetection({
    required this.kind,
    required this.toolUseId,
    required this.promptSummary,
    required this.agentId,
    required this.isError,
  });
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
    // 同理 dedupService:async 初始化 SharedPreferences,首次启动若未 ready,
    // 走 in-memory 兜底(hasHandledSync 在 _loaded=false 时返回 false 放行)。
    ref.read(dedupServiceProvider).valueOrNull,
  );
  ref.onDispose(r.dispose);
  return r;
});

final tabChatStateProvider = StreamProvider.family<TabChatState, String>(
  (ref, tabId) => ref.watch(chatRepositoryProvider).watch(tabId),
);
