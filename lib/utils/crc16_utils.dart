/// CRC-16/MODBUS 计算与校验
///
/// 多项式: 0xA001，小端序输出
class Crc16Utils {
  Crc16Utils._();

  static const int _poly = 0xA001;

  static final List<int> _table = () {
    final t = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        crc = (crc & 1 != 0) ? (crc >> 1) ^ _poly : crc >> 1;
      }
      t[i] = crc;
    }
    return t;
  }();

  /// 计算 CRC-16/MODBUS，返回 4 位小端 hex
  static String calculate(String hex) {
    int crc = 0xFFFF;
    for (int i = 0; i < hex.length; i += 2) {
      final b = int.parse(hex.substring(i, i + 2), radix: 16);
      crc = (crc >> 8) ^ _table[(crc ^ b) & 0xFF];
    }
    final lo = crc & 0xFF;
    final hi = (crc >> 8) & 0xFF;
    return '${lo.toRadixString(16).padLeft(2, '0')}'
        '${hi.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  /// 为 hex 命令追加 CRC
  static String append(String hex) => '$hex${calculate(hex)}';

  /// hex → bytes
  static List<int> hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    return List.generate(clean.length ~/ 2,
        (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16));
  }

  /// bytes → hex
  static String bytesToHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
