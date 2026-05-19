// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// 系统级通知：ask.question.pending 到达时，即便 App 不在前台也弹一条
// 高优先级 + 震动 + 大文本通知，方便用户即时知道 Claude 在等回答。
// 用户点通知打开 App → 自动落到对应 tab + 看到浮动卡片。
//
// 用 flutter_local_notifications + permission_handler 两个标准包实现。

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/protocol_message.dart';

const _channelId = 'cc_anywhere_ask';
const _channelName = 'Claude 提问';
const _channelDesc = 'Claude AskUserQuestion 实时提醒';

final askNotificationServiceProvider = Provider<AskNotificationService>((ref) {
  final svc = AskNotificationService();
  // ignore: discarded_futures
  svc.init();
  return svc;
});

class AskNotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 初始化通知 channel + 申请运行时权限（Android 13+ 必需 POST_NOTIFICATIONS）。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(init);

    // 创建/更新 channel（Android 8+ 必需）
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 运行时权限申请（Android 13+ / iOS）
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  /// 收到新 ask.question.pending 时调一次。
  /// 同一 request_id 不重复弹（用 hashCode 当 notification id 防止覆盖问题）。
  Future<void> notifyAskPending(AskQuestionPendingPayload payload) async {
    await init();
    final isToolApproval = payload.askKind == 'tool_approval';
    final title = isToolApproval
        ? '⚠ Claude 想执行 ${payload.toolName ?? "工具"}'
        : 'Claude 正在等你回答';
    String body = '';
    if (isToolApproval) {
      // tool_approval：展示 tool_input 摘要
      final ti = payload.toolInput;
      if (ti != null) {
        final cmd = ti['command'] ?? ti['file_path'] ?? ti.toString();
        body = '$cmd';
      } else {
        body = '点击查看并批准 / 拒绝';
      }
    } else {
      // user_question：第一题的 question 作为 body
      if (payload.questions.isNotEmpty) {
        final q = payload.questions.first;
        body = q['question'] as String? ?? '点击查看并回答';
      } else {
        body = '点击查看并回答';
      }
    }
    if (body.length > 200) body = '${body.substring(0, 200)}…';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        enableVibration: true,
        autoCancel: true,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
        ),
        // 红色高亮（仅 tool_approval）
        color: isToolApproval ? const Color(0xFFD9483A) : null,
      ),
    );

    final id = payload.requestId.hashCode & 0x7FFFFFFF;
    try {
      await _plugin.show(id, title, body, details,
          payload: payload.requestId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AskNotificationService.show failed: $e\n$st');
      }
    }
  }

  /// ask 已被回答 / 超时 / 取消 → 清掉对应通知。
  ///
  /// 延迟 3 秒再 cancel：winner-lock 仲裁可能在 < 1 秒内发生（用户在 Mac 上
  /// 先答了），如果立即 cancel，OPPO/小米/华为 等定制系统还没来得及显示
  /// 抬头横幅通知就被撤回，用户看不到震动 + 弹出效果，体验等同没通知。
  /// 延迟 3 秒后再 cancel，给系统足够时间至少把通知亮一下。
  Future<void> dismissAsk(String requestId) async {
    if (!_initialized) return;
    final id = requestId.hashCode & 0x7FFFFFFF;
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        await _plugin.cancel(id);
      } catch (_) {}
    });
  }
}

