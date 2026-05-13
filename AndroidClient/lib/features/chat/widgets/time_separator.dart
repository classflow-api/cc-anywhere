import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/color_tokens.dart';

class TimeSeparator extends StatelessWidget {
  final DateTime time;
  const TimeSeparator({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Center(
        child: Text(
          _format(time),
          style: TextStyle(
            fontSize: 10.5,
            color: t.textFaint,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  String _format(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tDate = DateTime(t.year, t.month, t.day);
    final diff = today.difference(tDate).inDays;
    final hm = DateFormat('HH:mm').format(t);
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    if (diff < 7) return DateFormat('EEEE HH:mm', 'zh_CN').format(t);
    return DateFormat('M月d日 HH:mm', 'zh_CN').format(t);
  }
}
