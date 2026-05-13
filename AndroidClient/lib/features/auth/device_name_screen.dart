import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_repository.dart';
import '../../data/device_repository.dart';
import '../../data/ws_client.dart';
import '../../models/server_config.dart';
import '../../routes/app_router.dart';
import '../../theme/color_tokens.dart';

/// 设备命名 + 绑定确认
class DeviceNameScreen extends ConsumerStatefulWidget {
  final ServerConfig pendingConfig;
  const DeviceNameScreen({super.key, required this.pendingConfig});

  @override
  ConsumerState<DeviceNameScreen> createState() => _DeviceNameScreenState();
}

class _DeviceNameScreenState extends ConsumerState<DeviceNameScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.pendingConfig.deviceName,
  );
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 用本机型号填充默认
    Future<void>.microtask(() async {
      final info = await ref.read(deviceRepositoryProvider).readLocal();
      if (mounted && _name.text == 'Android') {
        setState(() {
          _name.text = info.defaultDeviceName;
        });
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入设备名');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final cfg = widget.pendingConfig.copyWith(
        deviceName: name.length > 30 ? name.substring(0, 30) : name,
      );
      await ref.read(authRepositoryProvider).completeBind(cfg);
      if (!mounted) return;
      // 通知 router 刷新
      ref.invalidate(initialConfigProvider);
      context.go(AppRoutes.tabs);
    } on BindFailedException catch (e) {
      setState(() {
        _submitting = false;
        _error = switch (e.code) {
          'TOKEN_EXPIRED' => 'QR 码已失效，请重新扫描',
          'INVALID_TOKEN' => 'token 不正确',
          'REVOKED' => '该 token 已被撤销',
          _ => e.message,
        };
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = '无法连接到 Server：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _submitting ? null : () => context.pop(),
        ),
        title: const Text('给这台设备起个名字'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.bgElev,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.line),
            ),
            child: Row(
              children: [
                Icon(Icons.dns_rounded, color: t.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.pendingConfig.server}:${widget.pendingConfig.port}',
                        style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        'sub_token ${_maskToken(widget.pendingConfig.subToken)}',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('设备名',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: t.textFaint,
              )),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: t.bgInset,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line),
            ),
            child: TextField(
              controller: _name,
              maxLength: 30,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                counterText: '',
              ),
              style: TextStyle(color: t.text, fontSize: 15),
              enabled: !_submitting,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: t.danger.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: t.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(color: t.danger, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _bind,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成绑定'),
          ),
        ],
      ),
    );
  }

  String _maskToken(String tok) {
    if (tok.length <= 8) return '…${tok.substring(tok.length ~/ 2)}';
    return '…${tok.substring(tok.length - 6)}';
  }
}
