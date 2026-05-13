import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/server_config.dart';
import '../../routes/app_router.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/pulse_dot.dart';

/// 扫码页 — 1:1 对应 mobile-client.jsx MobileScan
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _handled = false;
  String? _error;

  late final AnimationController _laser = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    _laser.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final cfg = ServerConfig.tryParseQr(raw);
    if (cfg == null) {
      setState(() => _error = '二维码内容不正确，请确认是 cc-anywhere 的 QR');
      return;
    }
    _handled = true;
    _controller.stop();
    context.go(AppRoutes.deviceName, extra: cfg);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 实际相机预览
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, _) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '无法启动摄像头：${error.errorDetails?.message ?? error.errorCode.name}\n请使用手动输入',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
          // 半透明遮罩 + 中央扫描框
          Positioned.fill(child: CustomPaint(painter: _ScanMaskPainter())),
          // corner brackets + laser
          Center(
            child: SizedBox(
              width: 244,
              height: 244,
              child: Stack(
                children: [
                  // 4 个 corner brackets
                  ..._buildCorners(t.accent),
                  // laser
                  AnimatedBuilder(
                    animation: _laser,
                    builder: (_, __) {
                      final top = _laser.value * (244 - 4);
                      return Positioned(
                        top: top,
                        left: 8,
                        right: 8,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                t.accent.withValues(alpha: 0),
                                t.accent,
                                t.accent.withValues(alpha: 0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: t.accent.withValues(alpha: 0.8),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 顶部提示
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _CircleIcon(
                        icon: Icons.arrow_back,
                        onTap: () => context.pop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            _error ?? '将相机对准 Mac 上的 QR 码',
                            style: TextStyle(
                              fontSize: 13,
                              color: _error != null
                                  ? t.danger
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // 底部面板
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xB30F1116),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        PulseDot(color: t.accent, size: 8),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('正在搜索 QR 码…',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  )),
                              Text('cc-anywhere · v0.4.2',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0x8CFFFFFF),
                                  )),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.go(AppRoutes.manualInput),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              '手动输入',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  List<Widget> _buildCorners(Color color) {
    final shadow = [
      BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 12),
    ];
    Widget corner({
      double? top,
      double? bottom,
      double? left,
      double? right,
      required EdgeInsets edges,
      required BorderRadius radius,
    }) {
      return Positioned(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                  color: color, width: edges.top > 0 ? edges.top : 0),
              bottom: BorderSide(
                  color: color, width: edges.bottom > 0 ? edges.bottom : 0),
              left: BorderSide(
                  color: color, width: edges.left > 0 ? edges.left : 0),
              right: BorderSide(
                  color: color, width: edges.right > 0 ? edges.right : 0),
            ),
            borderRadius: radius,
            boxShadow: shadow,
          ),
        ),
      );
    }

    return [
      corner(
        top: -2,
        left: -2,
        edges: const EdgeInsets.only(top: 3, left: 3),
        radius: const BorderRadius.only(topLeft: Radius.circular(10)),
      ),
      corner(
        top: -2,
        right: -2,
        edges: const EdgeInsets.only(top: 3, right: 3),
        radius: const BorderRadius.only(topRight: Radius.circular(10)),
      ),
      corner(
        bottom: -2,
        left: -2,
        edges: const EdgeInsets.only(bottom: 3, left: 3),
        radius: const BorderRadius.only(bottomLeft: Radius.circular(10)),
      ),
      corner(
        bottom: -2,
        right: -2,
        edges: const EdgeInsets.only(bottom: 3, right: 3),
        radius: const BorderRadius.only(bottomRight: Radius.circular(10)),
      ),
    ];
  }
}

class _ScanMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x8C000000); // rgba(0,0,0,0.55)
    final outer = Path()..addRect(Offset.zero & size);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.5),
      width: 244,
      height: 244,
    );
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(28)));
    final combined = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(combined, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back, size: 16, color: Colors.white),
      ),
    );
  }
}
