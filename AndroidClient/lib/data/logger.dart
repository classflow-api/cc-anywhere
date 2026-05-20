import 'dart:async';
import 'dart:collection';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  const LogEntry(this.time, this.level, this.tag, this.message);

  String format() {
    final t = time.toIso8601String();
    final lv = level.name.toUpperCase().padRight(5);
    return '$t $lv [$tag] $message';
  }
}

/// 本地日志器 — 内存环形缓存 (最近 1000 条) + dart:developer 控制台输出
/// + 可选文件 mirror (Android app-specific external storage,adb pull 可拉取)
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _capacity = 1000;
  final Queue<LogEntry> _entries = ListQueue<LogEntry>();
  final StreamController<LogEntry> _stream = StreamController.broadcast();
  File? _fileSink;

  /// 初始化文件 sink — 写到 app-specific external storage
  /// (/sdcard/Android/data/<pkg>/files/cc-anywhere.log)。
  /// adb 拉取: adb pull /sdcard/Android/data/com.yoolines.ccanywhere.cc_anywhere/files/cc-anywhere.log
  /// main() 启动时 await 一次即可,失败静默忽略(不阻塞 App)。
  Future<void> initFileSink() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/cc-anywhere.log');
      // 启动时截断旧文件,避免无限增长
      await f.writeAsString(
          '=== AppLogger session start ${DateTime.now().toIso8601String()} ===\n',
          mode: FileMode.write,
          flush: true);
      _fileSink = f;
    } catch (_) {/* 静默 */}
  }

  Stream<LogEntry> get stream => _stream.stream;

  List<LogEntry> snapshot() => _entries.toList(growable: false);

  void debug(String tag, String msg) => _log(LogLevel.debug, tag, msg);
  void info(String tag, String msg) => _log(LogLevel.info, tag, msg);
  void warn(String tag, String msg) => _log(LogLevel.warn, tag, msg);
  void error(String tag, String msg, [Object? err, StackTrace? st]) {
    var line = msg;
    if (err != null) line += ' | err=$err';
    if (st != null) line += '\n$st';
    _log(LogLevel.error, tag, line);
  }

  void _log(LogLevel level, String tag, String msg) {
    final e = LogEntry(DateTime.now(), level, tag, msg);
    if (_entries.length >= _capacity) _entries.removeFirst();
    _entries.add(e);
    if (!_stream.isClosed) _stream.add(e);
    dev.log(msg, name: tag, level: switch (level) {
      LogLevel.debug => 500,
      LogLevel.info => 800,
      LogLevel.warn => 900,
      LogLevel.error => 1000,
    });
    // 文件 mirror(同步 append,fire-and-forget 失败不影响主流程)
    try {
      _fileSink?.writeAsStringSync(
        '${e.format()}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {/* 静默 */}
  }

  void clear() {
    _entries.clear();
  }

  String exportText() {
    return _entries.map((e) => e.format()).join('\n');
  }
}

final loggerProvider = Provider<AppLogger>((_) => AppLogger.instance);
