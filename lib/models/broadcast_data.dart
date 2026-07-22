/// 广播数据解析结果
///
/// 从 BLE 广播的 9 字节二进制包中解析设备信息。
///
/// 字节布局：
///   byte 0-1: Protocol (uint16 LE) → 4位 hex 字符串，如 "7030"
///   byte 2:   SOC (uint8, 0-100%)
///   byte 3-4: Voltage (uint16 LE, 0.01V) → ÷100 = V
///   byte 5-6: Current (int16 LE, 0.01A) → ÷100 = A
///   byte 7-8: Safety flags (uint16 LE, 16-bit bitmask)
class BroadcastData {
  /// 协议型号（4 位 hex）
  final String protocol;

  /// 电池电量百分比 (0-100)
  final int soc;

  /// 电压（V）
  final double voltage;

  /// 电流（A），正=充电，负=放电
  final double current;

  /// 安全标志位（16 bits，按 BitDesc 逐位解析）
  final int safetyFlags;

  /// 数据是否有效
  final bool isValid;

  const BroadcastData({
    required this.protocol,
    required this.soc,
    required this.voltage,
    required this.current,
    required this.safetyFlags,
    this.isValid = true,
  });

  /// 无效数据
  static const empty = BroadcastData(
    protocol: '----',
    soc: 0,
    voltage: 0,
    current: 0,
    safetyFlags: 0,
    isValid: false,
  );

  /// 从原始广播字节解析
  ///
  /// 自动兼容两种布局：
  ///   布局 A (9 bytes): protocol(2) + soc(1) + voltage(2) + current(2) + safety(2)
  ///   布局 B (7 bytes):              soc(1) + voltage(2) + current(2) + safety(2)
  factory BroadcastData.parse(List<int> bytes) {
    if (bytes.length < 7) return BroadcastData.empty;

    try {
      // 先尝试布局 A（含 protocol），校验 SOC/voltage 合理性
      if (bytes.length >= 9) {
        final result = _tryLayoutA(bytes);
        if (result != null) return result;
      }

      // 回退到布局 B（无 protocol）
      final result = _tryLayoutB(bytes);
      if (result != null) return result;
    } catch (_) {}

    return BroadcastData.empty;
  }

  /// 布局 A: protocol(2) + soc(1) + voltage(2) + current(2) + safety(2)
  static BroadcastData? _tryLayoutA(List<int> bytes) {
    final soc = bytes[2];
    final voltage = _uint16Le(bytes, 3) / 100.0;
    if (soc > 100 || voltage < 5 || voltage > 200) return null;

    return BroadcastData(
      protocol: _uint16Le(bytes, 0)
          .toRadixString(16)
          .padLeft(4, '0')
          .toUpperCase(),
      soc: soc,
      voltage: voltage,
      current: _int16Le(bytes, 5) / 100.0,
      safetyFlags: _uint16Le(bytes, 7),
    );
  }

  /// 布局 B: soc(1) + voltage(2) + current(2) + safety(2)
  static BroadcastData? _tryLayoutB(List<int> bytes) {
    final soc = bytes[0];
    final voltage = _uint16Le(bytes, 1) / 100.0;
    if (soc > 100 || voltage < 5 || voltage > 200) return null;

    return BroadcastData(
      protocol: '----',
      soc: soc,
      voltage: voltage,
      current: _int16Le(bytes, 3) / 100.0,
      safetyFlags: _uint16Le(bytes, 5),
    );
  }

  /// 模拟数据（用于 UI 开发测试）
  factory BroadcastData.mock() {
    return const BroadcastData(
      protocol: '7030',
      soc: 85,
      voltage: 76.69,
      current: -5.2,
      safetyFlags: (1 << 2) | (1 << 4), // SCD + RCA
    );
  }

  static int _uint16Le(List<int> bytes, int offset) =>
      (bytes[offset + 1] << 8) | bytes[offset];

  static int _int16Le(List<int> bytes, int offset) {
    int val = (bytes[offset + 1] << 8) | bytes[offset];
    if (val & 0x8000 != 0) val -= 0x10000;
    return val;
  }
}
