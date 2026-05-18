import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auth_repository.dart';
import 'data/logger.dart';
import 'data/ws_client.dart';
import 'routes/app_router.dart';
import 'services/ask_notification_service.dart';
import 'services/ask_question_controller.dart';
import 'theme/theme_data.dart';
import 'theme/theme_provider.dart';
import 'widgets/notification_toast.dart';

class CcAnywhereApp extends ConsumerStatefulWidget {
  const CcAnywhereApp({super.key});

  @override
  ConsumerState<CcAnywhereApp> createState() => _CcAnywhereAppState();
}

class _CcAnywhereAppState extends ConsumerState<CcAnywhereApp> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    // 启动时若有已保存配置则自动建立长连接
    final cfg = await ref.read(initialConfigProvider.future);
    if (!mounted) return;
    if (cfg != null) {
      ref.read(loggerProvider).info('Bootstrap', '已有 config，自动连接 ${cfg.server}');
      try {
        await ref.read(wsClientProvider).connect(cfg);
      } catch (e) {
        ref.read(loggerProvider).warn('Bootstrap', 'auto connect failed: $e');
      }
    } else {
      ref.read(loggerProvider).info('Bootstrap', '首次启动');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final mode = ref.watch(themeModeProvider);
    // 启动 toast service —— 触发 ws inbound 监听
    ref.watch(notificationToastServiceProvider);
    // Eager 创建 AskQuestionController + NotificationService — 这两个 Provider
    // 是 lazy 的，如果用户进入 chat_screen 之前没人 read/watch 它们，它们就
    // 不订阅 ws inbound，期间 Mac 推过来的 ask.question.pending 事件会丢失：
    // 既不弹系统通知，也不更新 state（用户后来进 chat 也看不到卡片）。
    // 在 App 顶层 eager 创建，让它们随 App 启动一起监听 ws。
    ref.watch(askQuestionControllerProvider);
    ref.watch(askNotificationServiceProvider);
    return MaterialApp.router(
      title: 'cc-anywhere',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: mode,
      theme: AppThemeData.build(brightness: Brightness.light),
      darkTheme: AppThemeData.build(brightness: Brightness.dark),
      builder: (context, child) {
        // 全局顶部 Toast 容器 —— R-F3-002 队列、R-F3-003 颜色由 widget 内部处理
        return NotificationToastHost(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
