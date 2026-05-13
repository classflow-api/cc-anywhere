import 'dart:async';
import 'dart:collection';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _capacity = 1000;
  final Queue<LogEntry> _entries = ListQueue<LogEntry>();
  final StreamController<LogEntry> _stream = StreamController.broadcast();

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
  }

  void clear() {
    _entries.clear();
  }

  String exportText() {
    return _entries.map((e) => e.format()).join('\n');
  }
}

final loggerProvider = Provider<AppLogger>((_) => AppLogger.instance);
