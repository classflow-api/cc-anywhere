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
            child: localPath != null && File(localPath).existsSync()
                ? Image.file(File(localPath), fit: BoxFit.cover)
                : ColoredBox(
                    color: t.bgInset,
                    child: Center(
                      child: Icon(Icons.image_rounded, color: t.textFaint),
                    ),
                  ),
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
}
