import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone 端 tool_use_id 去重服务。
///
/// 背景（详见技术实施文档 §4.7.4 + 需求规格说明书 §3.1 F5）：
///
/// AskUserQuestion 远程交互场景下,hook 实时推送（`ask.question.pending` /
/// `tool.progress.pre` / `tool.progress.post`）与 JSONL 旁观补拉（`msg.stream` /
/// `msg.history.response` 携带 tool_use / tool_result 行）双通道并存。
/// 若不去重,phone 端会对同一个 `tool_use_id` 渲染两次卡片(F5-S1 重复卡片缺陷)。
///
/// 业务规则（R-F5-001 ~ R-F5-004）：
/// - 同一 `tool_use_id` 只处理一次,无论来源通道。
/// - 已处理标记跨 App 重启持久化（SharedPreferences）。
/// - TTL 24h 自动过期,避免无限增长；Claude 单次会话内 tool_use_id 不会复用,24h
///   足以覆盖 hook → JSONL 写入 → server forward 的最长窗口。
/// - 清除绑定 / 用户主动重置时调用 [clear] 清空。
///
/// 为什么用 SharedPreferences:
/// - 项目已经依赖了（image_ref_store 等同样模式）,不引入新依赖。
/// - tool_use_id 总量有限（24h 内单设备活跃 tool 调用通常 < 1k 量级）,
///   一次性 JSON 序列化开销可接受。
class DedupService {
  DedupService(this._prefs);

  static const _ttlHours = 24;
  static const _key = 'cc_anywhere_handled_tool_use_ids';

  final SharedPreferences _prefs;

  /// in-memory 缓存:tool_use_id → 过期时刻。
  final Map<String, DateTime> _ttl = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = _prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is String) {
              final expire = DateTime.tryParse(v);
              if (expire != null) {
                _ttl[k.toString()] = expire;
              }
            }
          });
        }
      } catch (_) {
        // 持久化损坏:重新开始,不阻塞使用。
      }
    }
    _evictExpired();
    _loaded = true;
  }

  /// 检查并标记一个 tool_use_id。
  ///
  /// 返回 `true` 表示之前没见过、需要处理(调用方继续渲染卡片);
  /// 返回 `false` 表示已处理过,调用方跳过。
  ///
  /// `toolUseId` 为空字符串视为"无 id",直接返回 true 不参与去重 —
  /// 兼容历史记录(JSONL 中早期工具调用可能缺 id)。
  Future<bool> checkAndMark(String toolUseId) async {
    if (toolUseId.isEmpty) return true;
    await _ensureLoaded();
    _evictExpired();
    if (_ttl.containsKey(toolUseId)) return false;
    _ttl[toolUseId] = DateTime.now().add(const Duration(hours: _ttlHours));
    // fire-and-forget 写盘:in-memory 已立即生效,持久化失败不影响业务。
    unawaited(_persist());
    return true;
  }

  /// 仅查询是否已处理,不写入。供调试 / 异常路径使用。
  Future<bool> hasHandled(String toolUseId) async {
    if (toolUseId.isEmpty) return false;
    await _ensureLoaded();
    _evictExpired();
    return _ttl.containsKey(toolUseId);
  }

  /// 异步预热:启动期调用一次,后续可使用同步 API([hasHandledSync] /
  /// [markSync])在性能敏感路径上避免 await。
  Future<void> prewarm() => _ensureLoaded();

  /// 同步检查:仅在 [_loaded] 为 true 时返回准确结果;未加载时保守返回 false
  /// (放行调用方继续处理),后续异步路径会兜底。
  bool hasHandledSync(String toolUseId) {
    if (!_loaded || toolUseId.isEmpty) return false;
    _evictExpired();
    return _ttl.containsKey(toolUseId);
  }

  /// 同步标记:仅在 [_loaded] 为 true 时生效;未加载时 no-op
  /// (异步路径 [checkAndMark] 仍会兜底写入)。
  void markSync(String toolUseId) {
    if (!_loaded || toolUseId.isEmpty) return;
    _ttl[toolUseId] = DateTime.now().add(const Duration(hours: _ttlHours));
    unawaited(_persist());
  }

  void _evictExpired() {
    final now = DateTime.now();
    _ttl.removeWhere((_, expire) => expire.isBefore(now));
  }

  Future<void> _persist() async {
    final encoded = _ttl.map((k, v) => MapEntry(k, v.toIso8601String()));
    await _prefs.setString(_key, jsonEncode(encoded));
  }

  /// 解绑 / 主动重置时清空。
  Future<void> clear() async {
    _ttl.clear();
    _loaded = true;
    await _prefs.remove(_key);
  }
}

/// Provider:DedupService 依赖 SharedPreferences,启动时 prefetch。
final dedupServiceProvider = FutureProvider<DedupService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return DedupService(prefs);
});
