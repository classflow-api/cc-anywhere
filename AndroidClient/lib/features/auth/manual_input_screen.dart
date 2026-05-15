import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/server_config.dart';
import '../../routes/app_router.dart';
import '../../theme/color_tokens.dart';

/// 手动输入绑定信息页 — 极简表单
class ManualInputScreen extends ConsumerStatefulWidget {
  const ManualInputScreen({super.key});

  @override
  ConsumerState<ManualInputScreen> createState() => _ManualInputScreenState();
}

class _ManualInputScreenState extends ConsumerState<ManualInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _port = TextEditingController(text: '8443');
  final _token = TextEditingController();
  bool _trust = true;

  @override
  void dispose() {
    _server.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final cfg = ServerConfig(
      server: _server.text.trim(),
      port: int.parse(_port.text.trim()),
      subToken: _token.text.trim(),
      agentId: '',
      deviceName: 'Android',
      trustSelfSigned: _trust,
    );
    context.go(AppRoutes.deviceName, extra: cfg);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('手动输入'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              '请填写 Mac 端 cc-anywhere 显示的 Server 信息与 sub_token',
              style: TextStyle(fontSize: 13, color: t.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            _Field(
              label: 'Server 地址',
              controller: _server,
              hint: 'cc.example.com',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '必填' : null,
            ),
            const SizedBox(height: 14),
            _Field(
              label: '端口',
              controller: _port,
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0 || n > 65535) return '端口无效';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _Field(
              label: 'sub_token',
              controller: _token,
              hint: 'cc-……',
              maxLines: 2,
              validator: (v) =>
                  (v == null || v.trim().length < 8) ? 'token 太短' : null,
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              value: _trust,
              activeColor: t.accent,
              onChanged: (v) => setState(() => _trust = v),
              title: Text('信任自签证书',
                  style: TextStyle(color: t.text, fontSize: 14)),
              subtitle: Text(
                'Server 使用自签 TLS 时打开',
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: const Text('下一步')),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int? maxLines;
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
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
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: TextStyle(color: t.text, fontSize: 14),
            validator: validator,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
      ],
    );
  }
}
