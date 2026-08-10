import '../utils/crc16_utils.dart';

/// 数据类型转换管线 — 完全对齐参考项目 bms-utils.js
///
/// 读方向: hex → littleEndian → handleDataType → handleTemperature → handleOperation
/// 写方向: handleReverseOperation → handleReverseTemperature → handleReverseDataType → padStart → littleEndian → twoExchange
class DataTypeConverter {
  DataTypeConverter._();

  // ============================================================
  // 十六进制工具
  // ============================================================

  /// 清理十六进制字符串（去空格/非法字符/补零/转大写）
  static String cleanHexStr(String str) {
    String hex = str.replaceAll(RegExp(r'\s'), '');
    hex = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.isEmpty) throw ArgumentError('hex字符串不可为空');
    if (hex.length % 2 != 0) hex = '0$hex';
    return hex.toUpperCase();
  }

  /// 两两交换：每 4 个 hex 字符（2 字节）为一组，交换前后字节
  /// 例: "01020304" → "02010403"
  static String twoExchange(String hexStr) {
    final clean = cleanHexStr(hexStr);
    if (clean.length < 4) return clean; // 单字节无需交换
    final buf = StringBuffer();
    for (int i = 0; i < clean.length; i += 4) {
      final b1 = clean.substring(i, i + 2);
      final b2 = clean.substring(i + 2, i + 4);
      buf.write(b2);
      buf.write(b1);
    }
    return buf.toString();
  }

  /// 小端序：整个字符串按字节反转
  /// 例: "01020304" → "04030201"
  static String littleEndian(String hexStr) {
    final buf = StringBuffer();
    for (int i = hexStr.length; i > 0; i -= 2) {
      buf.write(hexStr.substring(i - 2, i));
    }
    return buf.toString();
  }

  // ============================================================
  // CRC 校验
  // ============================================================

  /// 校验 CRC-16/MODBUS（截最后 4 位比对）
  static bool verifyCRC(String hexStr) {
    final dataPart = hexStr.substring(0, hexStr.length - 4);
    final originalCrc = hexStr.substring(hexStr.length - 4);
    final calculatedCrc = Crc16Utils.calculate(dataPart);
    final ok = calculatedCrc == originalCrc;
    if (!ok) print('CRC FAIL: calc=$calculatedCrc recv=$originalCrc');
    return ok;
  }

  // ============================================================
  // 有符号/无符号转换
  // ============================================================

  /// 无符号 → 有符号（补码还原）
  /// [bitLength] 位宽
  static int toSignedDecimal(int value, int bitLength) {
    final signBitMask = 1 << (bitLength - 1);
    if ((value & signBitMask) != 0) {
      return value - (1 << bitLength);
    }
    return value;
  }

  /// 有符号 → 无符号 hex 字符串
  static String toUnsignedHex(int value, int bitLength) {
    final totalRange = 1 << bitLength;
    int unsigned = ((value % totalRange) + totalRange) % totalRange;
    return unsigned.toRadixString(16).padLeft(bitLength ~/ 4, '0');
  }

  // ============================================================
  // 位描述解析
  // ============================================================

  /// 解析位描述，返回 [{key, value}] 列表
  /// 例: bitDesc="CUV|OCD|SCD", binaryStr="101" → [{CUV,1},{OCD,0},{SCD,1}]
  static List<Map<String, dynamic>> parseBitDescription(
      String binaryStr, String bitDesc) {
    final keys = bitDesc.split('|').reversed.toList();
    return List.generate(keys.length, (i) {
      return <String, dynamic>{
        'key': keys[i],
        'value': binaryStr.length > i ? int.parse(binaryStr[i]) : 0,
      };
    });
  }

  /// 格式化 hex 值: "0001" → "0x0001"
  static String formatHexValue(String hex, {int padding = 4}) {
    final v = int.parse(hex, radix: 16);
    return '0x${v.toRadixString(16).padLeft(padding, '0').toUpperCase()}';
  }

  // ============================================================
  // 读方向 — handleDataType
  // ============================================================

  /// hex字符串 → 类型化数据
  static dynamic handleDataType(
      String hexValue, String? dataType, String? bitDesc) {
    final numericValue = int.parse(hexValue, radix: 16);

    switch (dataType) {
      case 'long':
      case 'short':
        return toSignedDecimal(numericValue, hexValue.length * 4);

      case 'unsigned long':
      case 'unsigned char':
      case 'unsigned short':
      case 'ushort Temper':
        return numericValue;

      case 'Time':
        // 格式: week(2) year(2) month(2) day(2) pm(2) hour(2) minute(2) second(2)
        final year = hexValue.substring(2, 4);
        final month = _hexToLastFiveBinThenHex(hexValue.substring(4, 6));
        final day = hexValue.substring(6, 8);
        final hour = hexValue.substring(10, 12);
        final minute = hexValue.substring(12, 14);
        final second = hexValue.substring(14, 16);
        return '${2000 + int.parse(year)}/$month/$day $hour:$minute:$second';

      case 'HEX':
        final bin = numericValue.toRadixString(2).padLeft(8, '0');
        if (bitDesc != null && bitDesc.isNotEmpty) {
          return parseBitDescription(bin, bitDesc);
        }
        return formatHexValue(hexValue);

      case '2HEX':
        final bin = numericValue.toRadixString(2).padLeft(16, '0');
        if (bitDesc != null && bitDesc.isNotEmpty) {
          return parseBitDescription(bin, bitDesc);
        }
        return formatHexValue(hexValue);

      default:
        return hexValue;
    }
  }

  // ============================================================
  // 读方向 — handleTemperature
  // ============================================================

  /// 温度特殊处理：ushort Temper → ÷10
  static dynamic handleTemperature(dynamic value, String? dataType) {
    if (dataType == 'ushort Temper' && value is num) {
      return value / 10.0;
    }
    return value;
  }

  // ============================================================
  // 读方向 — handleOperation
  // ============================================================

  /// 算术运算处理
  static dynamic handleOperation(
      dynamic value, String? dataType, String operation, double ratio) {
    // HEX/2HEX/Time 类型不参与算术运算
    if (dataType == '2HEX' || dataType == 'HEX' || dataType == 'Time') {
      return value;
    }
    if (value is! num) return value;

    return _performArithmetic(value, operation, ratio);
  }

  static num _performArithmetic(num value, String operation, double ratio) {
    switch (operation) {
      case '/':
        return value / ratio;
      case '*':
        return ratio != 1 ? value * ratio : value;
      case '+':
        return value + ratio;
      case '-':
        return value - ratio;
      default:
        return value;
    }
  }

  // ============================================================
  // 写方向 — handleReverseOperation
  // ============================================================

  static num handleReverseOperation(
      num value, String? dataType, String operation, double ratio) {
    if (dataType == '2HEX' || dataType == 'HEX') return value;

    const reverseMap = {'/': '*', '*': '/', '+': '-', '-': '+'};
    final revOp = reverseMap[operation] ?? operation;
    final result = _performArithmetic(value, revOp, ratio);
    return double.parse(result.toStringAsFixed(2));
  }

  // ============================================================
  // 写方向 — handleReverseTemperature
  // ============================================================

  static num handleReverseTemperature(num value, String? dataType) {
    if (dataType == 'ushort Temper') return value * 10;
    return value;
  }

  // ============================================================
  // 写方向 — handleReverseDataType
  // ============================================================

  static String handleReverseDataType(
      dynamic value, String? dataType, int length, String? bitDesc) {
    switch (dataType) {
      case 'long':
      case 'short':
        return toUnsignedHex((value as num).round(), length * 8);

      case 'unsigned long':
      case 'unsigned char':
      case 'unsigned short':
      case 'ushort Temper':
        return (value as num).round().toUnsigned(32).toRadixString(16);

      case 'Time':
        // 输入格式: "20001125235959"
        final s = value as String;
        final year = s.substring(2, 4);
        final month = s.substring(4, 6);
        final day = s.substring(6, 8);
        final hour = s.substring(8, 10);
        final minute = s.substring(10, 12);
        final second = s.substring(12, 14);
        final pm = (int.parse(hour) > 12) ? '01' : '00';
        return '00$year$month$day$pm$hour$minute$second';

      case 'HEX':
      case '2HEX':
        if (bitDesc != null && bitDesc.isNotEmpty) {
          return int.parse(value as String, radix: 2).toRadixString(16);
        }
        // value 可能是 num（UI输入）或 string（解析值如 "0x0002"）
        final intVal = value is num ? value.round() : int.parse(
          value.toString().replaceFirst(RegExp(r'^0x', caseSensitive: false), ''),
          radix: 16);
        return intVal.toRadixString(16);

      default:
        return value.toString();
    }
  }

  // ============================================================
  // 辅助
  // ============================================================

  /// hex → 取最后5位二进制 → 转回hex（用于Time类型的月份解析）
  static String _hexToLastFiveBinThenHex(String hexStr) {
    int num = int.parse(hexStr, radix: 16);
    String bin = num.toRadixString(2).padLeft(5, '0');
    String lastFive = bin.substring(bin.length - 5);
    int result = int.parse(lastFive, radix: 2);
    return result.toRadixString(16).padLeft(2, '0').toUpperCase();
  }
}
