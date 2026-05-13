import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 本机设备信息（model / android version）
class LocalDeviceInfo {
  final String model;
  final String osVersion;
  final String defaultDeviceName;

  const LocalDeviceInfo({
    required this.model,
    required this.osVersion,
    required this.defaultDeviceName,
  });
}

class DeviceRepository {
  Future<LocalDeviceInfo> readLocal() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return LocalDeviceInfo(
        model: info.model,
        osVersion: 'Android ${info.version.release}',
        defaultDeviceName: '${info.manufacturer} ${info.model}'.trim(),
      );
    } catch (_) {
      return const LocalDeviceInfo(
        model: 'Android',
        osVersion: 'Android',
        defaultDeviceName: 'Android Device',
      );
    }
  }
}

final deviceRepositoryProvider = Provider((_) => DeviceRepository());

final localDeviceInfoProvider = FutureProvider<LocalDeviceInfo>(
  (ref) => ref.read(deviceRepositoryProvider).readLocal(),
);
