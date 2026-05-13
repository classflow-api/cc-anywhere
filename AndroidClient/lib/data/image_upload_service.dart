import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/protocol_message.dart';
import 'logger.dart';
import 'ws_client.dart';

/// 图片上传单张失败（重试次数耗尽 / sha256 不匹配 / Server 拒绝）。
class ImageUploadException implements Exception {
  final String code;
  final String message;
  const ImageUploadException(this.code, this.message);
  @override
  String toString() => 'ImageUploadException($code): $message';
}

/// 实现「场景 2：发送图片」的上传链路（需求规格 §3.2 A4，业务流程图 §4.3）。
///
/// 流程：
///   1. 计算 sha256（package:crypto）
///   2. ws 发 `image.upload.begin` { tab_id, filename, size, sha256 }
///   3. 等待 `image.upload.url` 响应（或 `image.upload.expired` / `input.error`），10s 超时
///   4. dio HTTPS POST 文件字节到 upload_url，回调进度
///   5. 上传完成 → 由 Server 异步 forward `input.image` 给 Mac（客户端无需再发）
///
/// 失败重试：最多 3 次（R-A4-06）；超过 20MB 直接拒绝（R-A4-02）。
class ImageUploadService {
  ImageUploadService(this._ws, this._log);

  static const int _maxSize = 20 * 1024 * 1024; // 20 MB
  static const int _maxAttempts = 3; // R-A4-06
  static const Duration _beginTimeout = Duration(seconds: 10);
  static const Duration _httpTimeout = Duration(minutes: 2);

  final WsClient _ws;
  final AppLogger _log;
  final _uuid = const Uuid();

  /// 上传单张图片。
  ///
  /// - [tabId] 当前会话 Tab
  /// - [file] 本地文件（jpg/png/webp，调用方保证后缀；Server 不校验类型，只校验 size + sha256）
  /// - [onProgress] 0..1 上传进度回调（按字节计算，仅 HTTP POST 阶段；begin 等待阶段不回调）
  ///
  /// 注意：[text] 不在这里发；ChatRepository 负责在所有图片上传完成后单独发 `input.text`。
  /// 这样语义更清晰且与「场景 2 步骤 10」一致：先发图，再发文字。
  Future<void> upload({
    required String tabId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    // R-A4-02：大小硬校验
    final size = await file.length();
    if (size > _maxSize) {
      throw const ImageUploadException(
        ProtocolErrorCode.imageTooLarge,
        '图片超过 20 MB',
      );
    }

    // sha256
    final sha256Hex = await _sha256OfFile(file);
    final filename = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'image';

    // 重试循环：仅对网络/超时错误重试；IMAGE_TOO_LARGE / SHA256_MISMATCH 直接失败
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await _attemptOnce(
          tabId: tabId,
          filename: filename,
          size: size,
          sha256Hex: sha256Hex,
          file: file,
          onProgress: onProgress,
        );
        return; // 成功
      } on ImageUploadException catch (e) {
        // 服务端业务错误：不重试
        if (e.code == ProtocolErrorCode.imageTooLarge ||
            e.code == ProtocolErrorCode.sha256Mismatch) {
          rethrow;
        }
        lastError = e;
        _log.warn(
          'ImageUpload',
          'attempt $attempt/$_maxAttempts failed: $e',
        );
      } catch (e) {
        lastError = e;
        _log.warn(
          'ImageUpload',
          'attempt $attempt/$_maxAttempts failed: $e',
        );
      }
      if (attempt < _maxAttempts) {
        // 简单退避：1s / 2s
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
    throw ImageUploadException(
      ProtocolErrorCode.internal,
      '上传失败（重试 $_maxAttempts 次）：$lastError',
    );
  }

  Future<void> _attemptOnce({
    required String tabId,
    required String filename,
    required int size,
    required String sha256Hex,
    required File file,
    required void Function(double)? onProgress,
  }) async {
    final beginId = _uuid.v4();

    // 先挂监听，再发 begin，避免响应早于监听抵达
    final responseFuture = _ws.awaitResponse(
      forTypes: {
        ProtocolType.imageUploadUrl,
        ProtocolType.imageUploadExpired,
        ProtocolType.inputError,
      },
      // 协议未约定回包带 begin id（type 单一通道），所以按 type 命中即取首条
      timeout: _beginTimeout,
    );

    await _ws.send(ProtocolMessage(
      type: ProtocolType.imageUploadBegin,
      id: beginId,
      data: {
        'tab_id': tabId,
        'filename': filename,
        'size': size,
        'sha256': sha256Hex,
      },
    ));

    late ProtocolMessage resp;
    try {
      resp = await responseFuture;
    } on TimeoutException {
      throw const ImageUploadException(
        ProtocolErrorCode.internal,
        'Server 未在 10 秒内响应 image.upload.url',
      );
    }

    // 非成功类型 → 抛错（R-A4 上传失败语义）
    if (resp.type != ProtocolType.imageUploadUrl) {
      final code = (resp.data['code'] as String?) ??
          (resp.type == ProtocolType.imageUploadExpired
              ? ProtocolErrorCode.internal
              : ProtocolErrorCode.internal);
      final msg = (resp.data['message'] as String?) ??
          'Server 拒绝上传（${resp.type}）';
      throw ImageUploadException(code, msg);
    }

    final uploadUrl = resp.data['upload_url'] as String?;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw const ImageUploadException(
        ProtocolErrorCode.internal,
        'Server 响应缺少 upload_url',
      );
    }

    // HTTPS POST 文件字节
    await _httpPostFile(
      uploadUrl: uploadUrl,
      file: file,
      onProgress: onProgress,
    );
  }

  Future<void> _httpPostFile({
    required String uploadUrl,
    required File file,
    required void Function(double)? onProgress,
  }) async {
    final dio = _buildDio();
    try {
      final response = await dio.post<dynamic>(
        uploadUrl,
        data: file.openRead(),
        options: Options(
          headers: {
            HttpHeaders.contentLengthHeader: await file.length(),
            HttpHeaders.contentTypeHeader: 'application/octet-stream',
          },
          responseType: ResponseType.plain,
          sendTimeout: _httpTimeout,
          receiveTimeout: _httpTimeout,
          validateStatus: (code) => code != null && code >= 200 && code < 300,
        ),
        onSendProgress: (sent, total) {
          if (onProgress == null || total <= 0) return;
          onProgress(sent / total);
        },
      );
      _log.debug(
        'ImageUpload',
        'POST $uploadUrl -> ${response.statusCode}',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data?.toString() ?? e.message ?? '';
      // sha256 不一致是服务端返回 400 + "sha256 mismatch"，区分一下
      if (status == 400 && body.toLowerCase().contains('sha256')) {
        throw const ImageUploadException(
          ProtocolErrorCode.sha256Mismatch,
          'sha256 校验失败',
        );
      }
      throw ImageUploadException(
        ProtocolErrorCode.internal,
        'HTTP 上传失败（status=$status）：$body',
      );
    } finally {
      dio.close(force: true);
    }
  }

  Dio _buildDio() {
    final dio = Dio();
    // 自签证书：复用 WsClient 当前配置的 trustSelfSigned
    final cfg = _ws.currentConfig;
    if (cfg != null && cfg.trustSelfSigned) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final c = HttpClient();
          c.badCertificateCallback = (_, __, ___) => true;
          return c;
        },
      );
    }
    return dio;
  }

  /// 流式计算 sha256（不必整文件读入内存）。
  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

final imageUploadServiceProvider = Provider<ImageUploadService>((ref) {
  return ImageUploadService(
    ref.read(wsClientProvider),
    ref.read(loggerProvider),
  );
});
