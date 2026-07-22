import 'broadcast_data.dart';

/// 扫描到的 BLE 设备
class DeviceModel {
  final String deviceId;
  final String name;
  final int rssi;
  final BroadcastData advData;

  const DeviceModel({
    required this.deviceId,
    required this.name,
    required this.rssi,
    this.advData = BroadcastData.empty,
  });

  /// 显示名称 — 省略 DCSF 前缀及紧随的分隔符
  ///
  /// 例: "DCSF-XXXXX001" → "XXXXX001"
  ///     "DCSF_12345"    → "12345"
  String get displayName {
    final upper = name.toUpperCase();
    final idx = upper.indexOf('DCSF');
    if (idx < 0) return name;
    // 跳过 "DCSF" (4字符) + 可能的分隔符
    int start = idx + 4;
    if (start < name.length) {
      final ch = name[start];
      if (ch == '-' || ch == '_' || ch == ' ' || ch == ':' || ch == '+') start++;
    }
    return start < name.length ? name.substring(start) : name;
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceModel && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}
