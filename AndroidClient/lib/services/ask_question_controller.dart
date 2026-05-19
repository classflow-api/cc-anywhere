import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/logger.dart';
import '../data/ws_client.dart';
import '../models/protocol_message.dart';
import 'ask_notification_service.dart';

/// 单个 tab 当前活跃的 ask.question 实时态。
///
/// pending:队首正在展示的 pending 卡片（== queue.first if queue not empty）。
/// answered:winner 仲裁后 Mac App 广播给所有 phone 的回执（用于"已被 X 回答"展示,
/// 收到后 3 秒卡片自动 dismiss,在此期间禁用提交）。
/// timedOut:true 表示卡片应立即 dismiss(短暂 snackbar 由 UI 层弹)。
/// queueCount:含队首在内的 pending 总数（R-F6 队列 UI 用，≥2 时卡片顶部
///            显示"X/N 待审批"）。
/// queueIndex:当前显示的卡片在历史入队序列中的位置（始终 1 — 队首）。
///            R-F6-002：仅 queueCount ≥ 2 时 UI 才显示队列指示。
/// 注：当 queue 为空时 pending == null，UI 不渲染卡片。
@immutable
class AskQuestionState {
  final AskQuestionPendingPayload? pending;
  final AskQuestionAnsweredPayload? answered;
  final bool timedOut;
  final int queueCount;

  const AskQuestionState({
    this.pending,
    this.answered,
    this.timedOut = false,
    this.queueCount = 0,
  });

  AskQuestionState copyWith({
    AskQuestionPendingPayload? pending,
    AskQuestionAnsweredPayload? answered,
    bool? timedOut,
    int? queueCount,
    bool clearPending = false,
    bool clearAnswered = false,
  }) =>
      AskQuestionState(
        pending: clearPending ? null : (pending ?? this.pending),
        answered: clearAnswered ? null : (answered ?? this.answered),
        timedOut: timedOut ?? this.timedOut,
        queueCount: queueCount ?? this.queueCount,
      );

  static const empty = AskQuestionState();
}

/// AskUserQuestion 远程交互实时控制器。
///
/// 职责:
/// 1. 监听 [WsClient.inbound] 中的 `ask.question.pending` / `.answered` / `.timeout`
/// 2. 按 tab_id 维护当前活跃 pending(同一 tab 同时只展示一个)
/// 3. 提供 [submit] / [dismiss] 给 widget 调用
/// 4. 收到 answered → 3s 后自动 dismiss;timedOut → 立即 dismiss
///
/// 与 ChatRepository 解耦:它只负责事后模式(JSONL 解析的 toolUse + askUserQuestion 卡片),
/// 本控制器只负责实时模式。两条通道在 widget 层独立渲染,互不干扰。
class AskQuestionController {
  AskQuestionController(this._ws, this._log, this._notifier) {
    _sub = _ws.inbound.listen(_onInbound);
  }

  final WsClient _ws;
  final AppLogger _log;
  final AskNotificationService _notifier;
  final _uuid = const Uuid();
  StreamSubscription<ProtocolMessage>? _sub;

  // tabId → state
  final Map<String, AskQuestionState> _state = {};
  final Map<String, StreamController<AskQuestionState>> _ctrls = {};
  // request_id → 已用于 dismiss 的 3s timer(answered 状态)
  final Map<String, Timer> _autoDismissTimers = {};
  // tabId → 等待用户响应的 pending payload FIFO 队列（R-F6-001）。
  // queue.first 才是当前展示在 UI 上的卡片；其他为后到的、被 winner-lock 或
  // 用户提交时按需出队推进。新 pending 入队前按 requestId dedup。
  final Map<String, List<AskQuestionPendingPayload>> _queues = {};

  Stream<AskQuestionState> watch(String tabId) {
    final c = _ctrls.putIfAbsent(
      tabId,
      () => StreamController<AskQuestionState>.broadcast(),
    );
    Future<void>.microtask(() {
      c.add(_state[tabId] ?? AskQuestionState.empty);
    });
    return c.stream;
  }

  AskQuestionState snapshot(String tabId) =>
      _state[tabId] ?? AskQuestionState.empty;

  void _onInbound(ProtocolMessage m) {
    switch (m.type) {
      case ProtocolType.askQuestionPending:
        final p = AskQuestionPendingPayload.tryFrom(m.data);
        if (p == null) return;
        final queue = _queues.putIfAbsent(p.tabId, () => []);
        // R-F6-001：dedup — 相同 requestId 不重复入队（mac 端重试可能复推）。
        if (queue.any((x) => x.requestId == p.requestId)) {
          _log.info('AskQuestion',
              'pending ${p.requestId} dedup (already queued)');
          break;
        }
        queue.add(p);
        _log.info('AskQuestion',
            'pending ${p.requestId} tab=${p.tabId} queue=${queue.length}');
        _emitFromQueue(p.tabId);
        // 系统通知（即便 App 不在前台也强提醒）
        unawaited(_notifier.notifyAskPending(p));
        break;

      case ProtocolType.askQuestionAnswered:
        final a = AskQuestionAnsweredPayload.tryFrom(m.data);
        if (a == null) return;
        // 在所有 tab 的队列中找该 requestId 对应的 payload
        String? targetTab;
        _queues.forEach((tabId, q) {
          if (q.any((p) => p.requestId == a.requestId)) targetTab = tabId;
        });
        if (targetTab == null) return;
        _log.info('AskQuestion',
            'answered ${a.requestId} by=${a.answeredBy} tab=$targetTab');
        // 已答 → 取消系统通知
        unawaited(_notifier.dismissAsk(a.requestId));
        // R-F6-003：被 winner 仲裁掉的若是队首 → 走 3s 倒计时 banner（保留现有
        // 体验）；否则非队首被仲裁 → 静默从队列移除，不影响当前展示的卡片。
        final queue = _queues[targetTab!] ?? const [];
        final isHead = queue.isNotEmpty && queue.first.requestId == a.requestId;
        if (isHead) {
          final cur = _state[targetTab!] ?? AskQuestionState.empty;
          _update(targetTab!, cur.copyWith(answered: a));
          _autoDismissTimers.remove(a.requestId)?.cancel();
          _autoDismissTimers[a.requestId] = Timer(
            const Duration(seconds: 3),
            () => _dismissByRequestId(a.requestId),
          );
        } else {
          // 非队首：从队列剔除（targetPayload 必非空）
          _queues[targetTab!]?.removeWhere((x) => x.requestId == a.requestId);
          _emitFromQueue(targetTab!);
        }
        break;

      case ProtocolType.askQuestionTimeout:
        final t = AskQuestionTimeoutPayload.tryFrom(m.data);
        if (t == null) return;
        String? targetTab;
        _queues.forEach((tabId, q) {
          if (q.any((p) => p.requestId == t.requestId)) targetTab = tabId;
        });
        if (targetTab == null) return;
        _log.info('AskQuestion',
            'timeout ${t.requestId} reason=${t.reason} tab=$targetTab');
        // 超时 → 取消系统通知
        unawaited(_notifier.dismissAsk(t.requestId));
        // 队首 → 标 timedOut 让 UI 弹 snackbar；非队首 → 静默剔除
        final queue = _queues[targetTab!] ?? const [];
        final isHead = queue.isNotEmpty && queue.first.requestId == t.requestId;
        if (isHead) {
          final cur = _state[targetTab!] ?? AskQuestionState.empty;
          _update(targetTab!, cur.copyWith(timedOut: true));
          Future<void>.microtask(() => _dismissByRequestId(t.requestId));
        } else {
          _queues[targetTab!]?.removeWhere((x) => x.requestId == t.requestId);
          _emitFromQueue(targetTab!);
        }
        break;
    }
  }

  /// 从 queue 推导出当前展示的 state，并 emit。队列空 → empty。
  void _emitFromQueue(String tabId) {
    final q = _queues[tabId] ?? const [];
    final cur = _state[tabId] ?? AskQuestionState.empty;
    if (q.isEmpty) {
      _update(tabId, AskQuestionState.empty);
      return;
    }
    // 队首换人时清掉 answered/timedOut（属于上一个 requestId 的状态）
    final head = q.first;
    final keepAnswered = cur.answered?.requestId == head.requestId;
    _update(
      tabId,
      AskQuestionState(
        pending: head,
        answered: keepAnswered ? cur.answered : null,
        timedOut: false,
        queueCount: q.length,
      ),
    );
  }

  /// 提交答案:发 `ask.question.answer` 给 Server,Server 转 Mac App。
  Future<void> submit(String tabId, Map<String, String> answers) async {
    final cur = _state[tabId];
    final pending = cur?.pending;
    if (pending == null) return;
    if (cur?.answered != null) return; // R-F1-013:已有 winner 禁止再提交
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.askQuestionAnswer,
        id: _uuid.v4(),
        data: AskQuestionAnswerPayload(
          requestId: pending.requestId,
          answers: answers,
        ).toJson(),
      ));
      _log.info('AskQuestion',
          'answer sent ${pending.requestId} keys=${answers.keys.length}');
    } catch (e) {
      _log.warn('AskQuestion', 'send answer failed: $e');
      rethrow;
    }
  }

  /// 用户主动 dismiss(点取消按钮)— 不发 answer,只清本地 state。
  /// Server 端 winner 锁会继续等其他 endpoint,或 5 分钟后超时。
  ///
  /// 队列场景：仅出队当前队首并切到下一条 pending（如有）。Mac 端 winner 锁
  /// 不受影响 — 该 requestId 还可被其他端回答。
  void dismiss(String tabId) {
    final q = _queues[tabId];
    if (q == null || q.isEmpty) return;
    final head = q.removeAt(0);
    _autoDismissTimers.remove(head.requestId)?.cancel();
    _emitFromQueue(tabId);
  }

  /// 提交 tool_approval 决策(F4 危险工具远程批准):
  /// 发 `ask.tool_approval.answer` 给 Server,Server 转 Mac App。
  ///
  /// 与 [submit] 不同,本方法用于 askKind=tool_approval 的卡片:
  /// - decision 取值 "allow" | "deny"
  /// - reason 可选,仅 deny 时填用户附加原因(R-F4-005)
  /// - 本地立即 dismiss 卡片;winner 锁最终仲裁仍由 Mac 端做主
  ///   (Mac broadcast `ask.question.answered` 会同样命中"已被回答"
  ///    倒计时逻辑,但因本卡片已 dismiss,只是无副作用地落入 _state)
  Future<void> submitApproval(
    String tabId, {
    required String requestId,
    required String decision,
    String? reason,
  }) async {
    final cur = _state[tabId];
    if (cur?.answered != null) return; // 已有 winner 禁止再提交
    try {
      await _ws.send(ProtocolMessage(
        type: ProtocolType.askToolApprovalAnswer,
        id: _uuid.v4(),
        data: AskToolApprovalAnswerPayload(
          requestId: requestId,
          decision: decision,
          reason: reason,
        ).toJson(),
      ));
      _log.info(
        'AskQuestion',
        'tool_approval answer sent $requestId decision=$decision',
      );
    } catch (e) {
      _log.warn('AskQuestion', 'send tool_approval answer failed: $e');
      rethrow;
    }
    // 本地立即 dismiss(无需等 answered 回声;Mac winner 锁仍会广播给其他端)。
    // 队列场景：仅出队当前队首并切到下一条。
    final q = _queues[tabId];
    if (q != null && q.isNotEmpty && q.first.requestId == requestId) {
      q.removeAt(0);
      _autoDismissTimers.remove(requestId)?.cancel();
    }
    _emitFromQueue(tabId);
  }

  /// 通过 request_id 在所有 tab 中清空匹配 pending(answered 倒计时 / timeout 触发)。
  void _dismissByRequestId(String requestId) {
    _autoDismissTimers.remove(requestId)?.cancel();
    String? targetTab;
    _queues.forEach((tabId, q) {
      if (q.any((p) => p.requestId == requestId)) targetTab = tabId;
    });
    if (targetTab == null) return;
    _queues[targetTab!]?.removeWhere((p) => p.requestId == requestId);
    _emitFromQueue(targetTab!);
  }

  void _update(String tabId, AskQuestionState next) {
    _state[tabId] = next;
    _ctrls[tabId]?.add(next);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    for (final t in _autoDismissTimers.values) {
      t.cancel();
    }
    _autoDismissTimers.clear();
    for (final c in _ctrls.values) {
      await c.close();
    }
  }
}

final askQuestionControllerProvider = Provider<AskQuestionController>((ref) {
  final c = AskQuestionController(
    ref.read(wsClientProvider),
    ref.read(loggerProvider),
    ref.read(askNotificationServiceProvider),
  );
  ref.onDispose(c.dispose);
  return c;
});

/// 按 tab 订阅当前实时态(stream provider,UI 用 ref.watch)。
final askQuestionStateProvider =
    StreamProvider.family<AskQuestionState, String>(
  (ref, tabId) => ref.watch(askQuestionControllerProvider).watch(tabId),
);
