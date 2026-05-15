import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 持久化保存 (filename → upload_id) 映射,用于:
/// - phone 端发图上传成功后记录 image_id
/// - 后续从 JSONL 解析到 `@<inbox-path>` user message text 时,
///   按 filename 反查 upload_id,向 server 请求 image.download.url 拿可预览 URL
///
/// 简单 key-value(SharedPreferences),够用;键空间不大(图片数有限)。
/// App 卸载重装会清,这是 Android 行为,可接受 — 用户重装后看历史本来就需要重新交互。
class ImageRefStore {
  ImageRefStore(this._prefs);

  static const _key = 'image_refs_v1';
  final SharedPreferences _prefs;

  /// in-memory 缓存,启动时从 SharedPreferences 加载。
  /// key = filename (basename),value = upload_id。
  final Map<String, String> _map = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = _prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          _map.addAll(j.map((k, v) => MapEntry(k.toString(), v.toString())));
        }
      } catch (_) {/* corrupt — start fresh */}
    }
    _loaded = true;
  }

  Future<String?> getUploadId(String filename) async {
    await _ensureLoaded();
    return _map[filename];
  }

  /// 记录 filename → upload_id。同名后写覆盖前(重发同名图片以新为准)。
  Future<void> put(String filename, String uploadId) async {
    await _ensureLoaded();
    if (_map[filename] == uploadId) return;
    _map[filename] = uploadId;
    await _prefs.setString(_key, jsonEncode(_map));
  }
}

final imageRefStoreProvider = FutureProvider<ImageRefStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return ImageRefStore(prefs);
});
