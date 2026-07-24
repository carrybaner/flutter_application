/// SN 码解析工具 — 从二维码内容中提取设备 SN
class SnParser {
  SnParser._();

  /// 从 QR 结果中尝试提取 SN 码
  ///
  /// 支持格式：
  ///   https://xxx.com?sn=DCSF-3998260707064
  ///   https://xxx.com?SN=3998260707064&type=24S
  ///   SN=3998260707064
  ///   DCSF-3998260707064         (直接就是设备名)
  ///   3998260707064              (直接就是纯 SN)
  ///
  /// 返回 null 表示未识别到有效 SN
  static String? extract(String raw) {
    if (raw.isEmpty) return null;

    // URL decode
    var decoded = Uri.decodeFull(raw).trim();

    // 去掉首尾的引号和空白
    decoded = decoded.replaceAll(RegExp(r"""^["'\s]+|["'\s]+$"""), "");

    // 优先匹配 sn= / SN= 参数
    final snParam = RegExp(r'[?&]?[Ss][Nn]\s*=\s*([^&\s]+)');
    final match = snParam.firstMatch(decoded);
    if (match != null) {
      final sn = match.group(1)!.trim();
      if (_isValidSn(sn)) return sn;
    }

    // 如果没匹配到 sn= 参数，整个字符串可能就是设备名/SN
    if (_isValidSn(decoded)) return decoded;

    return null;
  }

  /// 检查是否像合法的 SN/设备名
  static bool _isValidSn(String s) {
    if (s.length < 6) return false;
    // 典型格式: DCSF-3998260707064 或 DCSF_A12345678 或 纯数字字母
    final cleaned = s.replaceAll(RegExp(r'^DCSF[_\-:+\s]?'), '');
    return cleaned.length >= 5 && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(cleaned);
  }
}
