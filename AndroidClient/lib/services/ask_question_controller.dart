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
/// pending:从 `ask.question.pending` 收到的题目载荷。
/// answered:winner 仲裁后 Mac App 广播给所有 phone 的回执（用于"已被 X 回答"展示,
/// 收到后 3 秒卡片自动 dismiss,在此期间禁用提交）。
/// timedOut:true 表示卡片应立即 dismiss(短暂 snackbar 由 UI 层弹)。
@immutable
class AskQuestionState {
  final AskQuestionPendingPayload? pending;
  final AskQuestionAnsweredPayload? answered;
  final bool timedOut;

  const AskQuestionState({
    this.pending,
    this.answered,
    this.timedOut = false,
  });

  AskQuestionState copyWith({
    AskQuestionPendingPayload? pending,
    AskQuestionAnsweredPayload? answered,
    bool? timedOut,
    bool clearPending = false,
    bool clearAnswered = false,
  }) =>
      AskQuestionState(
        pending: clearPending ? null : (pending ?? this.pending),
        answered: clearAnswered ? null : (answered ?? this.answered),
        timedOut: timedOut ?? this.timedOut,
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
        _log.info('AskQuestion', 'pending ${p.requestId} tab=${p.tabId}');
        _update(p.tabId, AskQuestionState(pending: p));
        // 系统通知（即便 App 不在前台也强提醒）
        unawaited(_notifier.notifyAskPending(p));
        break;

      case ProtocolType.askQuestionAnswered:
        final a = AskQuestionAnsweredPayload.tryFrom(m.data);
        if (a == null) return;
        // 找到 request_id 对应的 tab(扫一遍 _state),通常就 1-2 个 tab,O(N) 可以接受。
        String? targetTab;
        _state.forEach((tabId, st) {
          if (st.pending?.requestId == a.requestId) targetTab = tabId;
        });
        if (targetTab == null) return;
        _log.info('AskQuestion',
            'answered ${a.requestId} by=${a.answeredBy} tab=$targetTab');
        final cur = _state[targetTab!] ?? AskQuestionState.empty;
        _update(targetTab!, cur.copyWith(answered: a));
        // 已答 → 取消系统通知
        unawaited(_notifier.dismissAsk(a.requestId));
        // 3 秒后自动 dismiss(对齐 Mac 端 recentlyAnswered banner 行为)
        _autoDismissTimers.remove(a.requestId)?.cancel();
        _autoDismissTimers[a.requestId] = Timer(
          const Duration(seconds: 3),
          () => _dismissByRequestId(a.requestId),
        );
        break;

      case ProtocolType.askQuestionTimeout:
        final t = AskQuestionTimeoutPayload.tryFrom(m.data);
        if (t == null) return;
        String? targetTab;
        _state.forEach((tabId, st) {
          if (st.pending?.requestId == t.requestId) targetTab = tabId;
        });
        if (targetTab == null) return;
        _log.info('AskQuestion',
            'timeout ${t.requestId} reason=${t.reason} tab=$targetTab');
        // 标 timedOut → UI 层取 snapshot 弹 snackbar + 立即清空
        final cur = _state[targetTab!] ?? AskQuestionState.empty;
        _update(targetTab!, cur.copyWith(timedOut: true));
        // 超时 → 取消系统通知
        unawaited(_notifier.dismissAsk(t.requestId));
        // 下一个 frame 清空(给 UI 一帧时间读 timedOut 状态弹 snackbar)
        Future<void>.microtask(() => _dismissByRequestId(t.requestId));
        break;
    }
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
  void dismiss(String tabId) {
    final cur = _state[tabId];
    if (cur == null) return;
    _update(tabId, AskQuestionState.empty);
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
    // 本地立即 dismiss(无需等 answered 回声;Mac winner 锁仍会广播给其他端)
    _update(tabId, AskQuestionState.empty);
  }

  /// 通过 request_id 在所有 tab 中清空匹配 pending(answered 倒计时 / timeout 触发)。
  void _dismissByRequestId(String requestId) {
    _autoDismissTimers.remove(requestId)?.cancel();
    String? targetTab;
    _state.forEach((tabId, st) {
      if (st.pending?.requestId == requestId) targetTab = tabId;
    });
    if (targetTab == null) return;
    _update(targetTab!, AskQuestionState.empty);
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
