import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routes/app_router.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/aurora_orbs.dart';

/// 欢迎页 — 1:1 对应 mobile-client.jsx MobileWelcome
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: AuroraOrbs()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 大图标
                  _BigMark(),
                  const SizedBox(height: 36),
                  Text(
                    'CC-ANYWHERE · V0.4.2',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      color: t.textFaint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('你的 Claude',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: -0.8,
                        color: t.text,
                      )),
                  // 渐变文字 "随处可达"
                  ShaderMask(
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [t.accent, t.assistantAvatarStart],
                    ).createShader(rect),
                    blendMode: BlendMode.srcIn,
                    child: const Text(
                      '随处可达',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: -0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      '扫一扫绑定你的 Mac, 让命令行 AI 在通勤路上也能继续推进任务',
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const _FeatureChips(),
                  const SizedBox(height: 20),
                  _ShinyPrimaryButton(
                    icon: Icons.qr_code_2_rounded,
                    label: '扫码绑定 Mac',
                    onTap: () => context.push(AppRoutes.scan),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: () => context.push(AppRoutes.manualInput),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 12, color: t.textMuted),
                          children: [
                            const TextSpan(text: '没法扫码? '),
                            TextSpan(
                              text: '手动输入',
                              style: TextStyle(
                                color: t.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigMark extends StatefulWidget {
  @override
  State<_BigMark> createState() => _BigMarkState();
}

class _BigMarkState extends State<_BigMark> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.accent, t.assistantAvatarStart],
        ),
        boxShadow: [
          BoxShadow(
            color: t.accent.withValues(alpha: 0.45),
            blurRadius: 48,
            offset: const Offset(0, 20),
            spreadRadius: -16,
          ),
        ],
      ),
      child: Stack(
        children: [
          // inner pulse highlight
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const RadialGradient(
                    center: Alignment(-0.4, -0.4),
                    radius: 0.7,
                    colors: [
                      Color(0x73FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Center(
            child: Text(
              'cc',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 8,
            child: FadeTransition(
              opacity:
                  Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
                parent: _blink,
                curve: const Interval(0.5, 1.0),
              )),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChips extends StatelessWidget {
  const _FeatureChips();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = [
      (Icons.terminal_rounded, '集中管理多 Tab 会话', '一目了然'),
      (Icons.auto_awesome_rounded, '远程批准 tool_use', '< 500ms 双向'),
      (Icons.image_rounded, '随手发图给 Claude', '路上灵感即接即用'),
    ];
    return Column(
      children: [
        for (final f in items) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(f.$1, size: 15, color: t.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          )),
                      Text(f.$3,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: t.textMuted,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (f != items.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 流光按钮 — 渐变 + 上方 sheen 滚动
class _ShinyPrimaryButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ShinyPrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ShinyPrimaryButton> createState() => _ShinyPrimaryButtonState();
}

class _ShinyPrimaryButtonState extends State<_ShinyPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.accent, t.accentGradEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: t.accent.withValues(alpha: 0.45),
              blurRadius: 32,
              offset: const Offset(0, 12),
              spreadRadius: -10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // sheen
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  final t = _ctrl.value;
                  return Align(
                    alignment: Alignment(-1 + t * 2, 0),
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1.0,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0x00FFFFFF),
                              Color(0x4DFFFFFF),
                              Color(0x00FFFFFF),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon,
                      size: 18, color: const Color(0xFF001019)),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF001019),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
