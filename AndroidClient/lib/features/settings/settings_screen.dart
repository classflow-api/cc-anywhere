import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_repository.dart';
import '../../data/secure_storage.dart';
import '../../data/ws_client.dart';
import '../../models/server_config.dart';
import '../../routes/app_router.dart';
import '../../theme/color_tokens.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_pill.dart';

/// Mask a sub_token for UI display, keeping the last 4 characters when
/// possible. Safe for tokens shorter than 4 characters (avoids the
/// RangeError that `String.substring` / `num.clamp` would otherwise throw).
String _maskSubToken(String? token) {
  if (token == null || token.isEmpty) return '…';
  if (token.length <= 4) return '…$token';
  return '…${token.substring(token.length - 4)}';
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final cfg = ref.watch(initialConfigProvider).valueOrNull;
    final wsState = ref.watch(wsConnectionStateProvider).valueOrNull;
    final macOnline = (ref.watch(macPresenceProvider).valueOrNull ?? MacPresence.unknown) ==
        MacPresence.online;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _DeviceCard(
            deviceName: cfg?.deviceName ?? 'Android',
            subTokenSuffix: _maskSubToken(cfg?.subToken),
            online: macOnline && wsState == WsConnectionState.connected,
          ),
          const SizedBox(height: 18),
          const SectionLabel('Server', padding: EdgeInsets.only(left: 4)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: t.bgElev,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.line),
            ),
            child: Column(
              children: [
                _SettingsRow(
                  icon: Icons.wifi_rounded,
                  label: 'Server 地址',
                  value: cfg == null
                      ? '—'
                      : '${cfg.server}:${cfg.port}',
                ),
                _Divider(),
                _SettingsRow(
                  icon: Icons.memory_rounded,
                  label: 'agent_id',
                  value: cfg?.agentId.isEmpty ?? true ? '—' : cfg!.agentId,
                ),
                _Divider(),
                _Divider(),
                if (cfg != null)
                  _TrustSelfSignedRow(
                    value: cfg.trustSelfSigned,
                    onChanged: (next) => _setTrustSelfSigned(ref, cfg, next),
                  ),
                _Divider(),
                _SettingsRow(
                  icon: Icons.history_rounded,
                  label: '查看连接日志',
                  onTap: () => context.push(AppRoutes.logs),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('外观', padding: EdgeInsets.only(left: 4)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: t.bgElev,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.line),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    themeMode == ThemeMode.dark
                        ? Icons.dark_mode_rounded
                        : (themeMode == ThemeMode.light
                            ? Icons.light_mode_rounded
                            : Icons.settings_brightness_rounded),
                    size: 18,
                    color: t.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('外观模式',
                        style:
                            TextStyle(color: t.text, fontSize: 14)),
                  ),
                  _ThemeSegment(
                    selected: themeMode,
                    onSelected: (m) =>
                        ref.read(themeModeProvider.notifier).setMode(m),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _DangerCard(
            label: '解绑此设备',
            icon: Icons.logout_rounded,
            onTap: () => _confirmUnbind(context, ref),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'v0.4.2 · build 2026.05.13',
              style: TextStyle(
                fontSize: 11,
                color: t.textFaint,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 切换 trust_self_signed:写入 storage,刷新 provider,重连 WS 使新设置生效。
  Future<void> _setTrustSelfSigned(
      WidgetRef ref, ServerConfig current, bool next) async {
    if (current.trustSelfSigned == next) return;
    final updated = current.copyWith(trustSelfSigned: next);
    await ref.read(secureStorageProvider).writeConfig(updated);
    ref.invalidate(initialConfigProvider);
    // 用新的 trust 设置重新建立 TLS 连接
    await ref.read(wsClientProvider).connect(updated);
  }

  Future<void> _confirmUnbind(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定解绑？'),
        content: const Text('解绑后将清除本地所有数据并需要重新扫码绑定。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authRepositoryProvider).selfUnbind();
    // 同时清理 storage（保险）
    await ref.read(secureStorageProvider).clearAll();
    ref.invalidate(initialConfigProvider);
    if (context.mounted) context.go(AppRoutes.onboarding);
  }
}

class _DeviceCard extends StatelessWidget {
  final String deviceName;
  final String subTokenSuffix;
  final bool online;
  const _DeviceCard({
    required this.deviceName,
    required this.subTokenSuffix,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.accentSoft, t.bgElev],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('本机'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [t.accent, t.assistantAvatarStart],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: t.accent.withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.devices_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(deviceName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          'sub_token $subTokenSuffix',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: t.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  StatusPill(
                    dotColor: online ? t.success : t.textFaint,
                    text: online ? '在线' : '离线',
                    accent: online,
                  ),
                  StatusPill(
                    icon: Icon(Icons.lock_outline,
                        size: 11, color: t.textMuted),
                    text: 'TLS 1.3',
                  ),
                ],
              ),
            ],
          ),
        ),
        // 渐变 blob 装饰
        Positioned(
          right: -30,
          top: -30,
          child: IgnorePointer(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: t.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: t.text, fontSize: 14),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: TextStyle(
                  fontSize: 12,
                  color: t.textMuted,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: t.textFaint),
          ],
        ),
      ),
    );
  }
}

class _TrustSelfSignedRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _TrustSelfSignedRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: t.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('信任自签证书',
                    style: TextStyle(color: t.text, fontSize: 14)),
                const SizedBox(height: 2),
                Text('私有 VPS 自签场景需开启;关闭后将严格校验 CA',
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: context.tokens.line,
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;
  const _ThemeSegment({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const items = [
      (ThemeMode.light, '浅色'),
      (ThemeMode.dark, '深色'),
      (ThemeMode.system, '跟随系统'),
    ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.bgInset,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            GestureDetector(
              onTap: () => onSelected(item.$1),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: selected == item.$1 ? t.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected == item.$1 ? t.accentFg : t.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DangerCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DangerCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: t.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.danger,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: t.danger),
          ],
        ),
      ),
    );
  }
}
