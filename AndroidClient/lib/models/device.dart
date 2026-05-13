/// 已绑定的手机设备（Mac 端会列出，此处仅本地查看用）
class DeviceInfo {
  final String id;
  final String deviceName;
  final String? deviceModel;
  final String? osVersion;
  final DateTime? lastSeenAt;
  final bool online;

  const DeviceInfo({
    required this.id,
    required this.deviceName,
    this.deviceModel,
    this.osVersion,
    this.lastSeenAt,
    this.online = false,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        deviceName: (j['device_name'] as String?) ?? '',
        deviceModel: j['device_model'] as String?,
        osVersion: j['os_version'] as String?,
        lastSeenAt: j['last_seen_at'] != null
            ? DateTime.tryParse(j['last_seen_at'] as String)
            : null,
        online: (j['online'] as bool?) ?? false,
      );
}
