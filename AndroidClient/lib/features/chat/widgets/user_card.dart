import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

/// 用户消息气泡 — 右对齐渐变 + 不对称圆角 (18 18 4 18)
class UserCard extends StatelessWidget {
  final Message message;
  final VoidCallback? onRetry;
  const UserCard({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pending = message.isLocalPending;
    final failed = message.sendFailed;

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [t.accent, t.accentGradEnd],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: t.accent.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: Opacity(
                  opacity: pending ? 0.7 : 1,
                  child: Text(
                    message.text ?? '',
                    style: TextStyle(
                      color: t.accentFg,
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (pending)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: t.textFaint,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('发送中…',
                          style: TextStyle(
                            color: t.textFaint,
                            fontSize: 11,
                          )),
                    ],
                  ),
                ),
              if (failed)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: GestureDetector(
                    onTap: onRetry,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 14, color: t.danger),
                        const SizedBox(width: 4),
                        Text('发送失败 · 点击重试',
                            style: TextStyle(
                              color: t.danger,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
