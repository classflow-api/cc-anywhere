import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import '../features/auth/device_name_screen.dart';
import '../features/auth/manual_input_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/auth/qr_scanner_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/logs/log_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tabs/tab_list_screen.dart';
import '../models/server_config.dart';

/// 路由路径常量
abstract class AppRoutes {
  static const onboarding = '/onboarding';
  static const scan = '/scan';
  static const manualInput = '/manual';
  static const deviceName = '/device-name';
  static const tabs = '/tabs';
  static const chat = '/chat';
  static const settings = '/settings';
  static const logs = '/logs';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // initialConfigProvider 异步 resolve 时,router 必须重新评估 redirect,
  // 否则首次启动会停在 onboarding(cfg=null),即使后续 provider 加载到 cfg
  // redirect 也不会重跑。用 ValueNotifier + ref.listen 触发 router 刷新。
  final refresh = ValueNotifier<int>(0);
  ref.listen<AsyncValue<ServerConfig?>>(initialConfigProvider, (_, __) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.onboarding,
    refreshListenable: refresh,
    redirect: (context, state) {
      // 首次进入时根据 initialConfig 跳转
      final cfg = ref.read(initialConfigProvider).asData?.value;
      final loc = state.matchedLocation;
      if (cfg != null &&
          (loc == AppRoutes.onboarding ||
              loc == AppRoutes.scan ||
              loc == AppRoutes.manualInput ||
              loc == AppRoutes.deviceName)) {
        return AppRoutes.tabs;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.scan,
        builder: (_, __) => const QrScannerScreen(),
      ),
      GoRoute(
        path: AppRoutes.manualInput,
        builder: (_, __) => const ManualInputScreen(),
      ),
      GoRoute(
        path: AppRoutes.deviceName,
        builder: (_, state) {
          final cfg = state.extra as ServerConfig;
          return DeviceNameScreen(pendingConfig: cfg);
        },
      ),
      GoRoute(
        path: AppRoutes.tabs,
        builder: (_, __) => const TabListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.chat}/:tabId',
        builder: (_, state) {
          final tabId = state.pathParameters['tabId'] ?? '';
          final tabName = (state.extra is Map)
              ? (state.extra as Map)['name'] as String?
              : null;
          return ChatScreen(tabId: tabId, initialTabName: tabName);
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.logs,
        builder: (_, __) => const LogScreen(),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('路由错误: ${state.error}')),
    ),
  );
});
