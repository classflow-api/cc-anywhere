import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/logger.dart';
import '../../theme/color_tokens.dart';

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final log = ref.read(loggerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('日志'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: log.exportText()));
              messenger.showSnackBar(
                const SnackBar(content: Text('日志已复制到剪贴板')),
              );
            },
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              log.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: StreamBuilder<LogEntry>(
        stream: log.stream,
        builder: (_, __) {
          final entries = log.snapshot();
          if (entries.isEmpty) {
            return Center(
              child: Text('暂无日志', style: TextStyle(color: t.textMuted)),
            );
          }
          return ListView.builder(
            reverse: false,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              final color = switch (e.level) {
                LogLevel.debug => t.textFaint,
                LogLevel.info => t.text,
                LogLevel.warn => t.warn,
                LogLevel.error => t.danger,
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(
                  e.format(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: color,
                    height: 1.4,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
