import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../theme/color_tokens.dart';

class AttachmentCard extends StatelessWidget {
  final Message message;
  const AttachmentCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isUser = message.role == MessageRole.user;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final localPath = message.attachmentLocalPath;

    final card = Container(
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: t.bgElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _buildImage(t, localPath, message.attachmentRemoteUrl),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.attachmentFilename != null)
                  Text(
                    message.attachmentFilename!,
                    style: TextStyle(
                      fontSize: 12,
                      color: t.text,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (message.uploadProgress != null &&
                    message.uploadProgress! < 1) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(
                      value: message.uploadProgress,
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '上传中 ${(message.uploadProgress! * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 10.5, color: t.textFaint),
                  ),
                ],
                if (message.uploadError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '上传失败：${message.uploadError}',
                    style: TextStyle(fontSize: 11, color: t.danger),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(alignment: align, child: card),
    );
  }

  static const _imageExts = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif'
  };

  bool _isImageFile(String? filename) {
    if (filename == null) return false;
    final p = filename.toLowerCase();
    final i = p.lastIndexOf('.');
    if (i < 0) return false;
    return _imageExts.contains(p.substring(i));
  }

  /// 优先本地文件预览(发送时),其次 server 下载 URL(历史消息),
  /// 非图片文件 / 加载失败 → 通用文件图标 + 文件名。
  Widget _buildImage(ColorTokens t, String? localPath, String? remoteUrl) {
    final isImg = _isImageFile(message.attachmentFilename) ||
        _isImageFile(localPath?.split('/').last);
    if (!isImg) {
      return _fileIcon(t);
    }
    if (localPath != null && File(localPath).existsSync()) {
      return Image.file(File(localPath), fit: BoxFit.cover);
    }
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return Image.network(
        remoteUrl,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return ColoredBox(
            color: t.bgInset,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => ColoredBox(
          color: t.bgInset,
          child: Center(child: Icon(Icons.broken_image_rounded, color: t.textFaint)),
        ),
      );
    }
    return ColoredBox(
      color: t.bgInset,
      child: Center(child: Icon(Icons.image_rounded, color: t.textFaint)),
    );
  }

  Widget _fileIcon(ColorTokens t) {
    return ColoredBox(
      color: t.bgInset,
      child: Center(child: Icon(Icons.insert_drive_file_outlined, color: t.textMuted, size: 44)),
    );
  }
}
