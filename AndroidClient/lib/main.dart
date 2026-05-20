import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/logger.dart';

/// 让 Image.network / dart:io HttpClient 都接受 server 自签证书。
/// cc-anywhere 是私有部署工具,Server 用户的内网/自有 VPS 用自签证书是常态;
/// 同 WsClient / ImageDownloader 的 trustSelfSigned 语义保持一致。
class _TrustAllCertHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, __, ___) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TrustAllCertHttpOverrides();
  // 状态栏沉浸（深色默认）
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B0E14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await initializeDateFormatting('zh_CN');
  // 启动文件日志 mirror,adb pull 可拉取:
  // adb pull /sdcard/Android/data/com.yoolines.ccanywhere.cc_anywhere/files/cc-anywhere.log
  await AppLogger.instance.initFileSink();
  runApp(const ProviderScope(child: CcAnywhereApp()));
}
