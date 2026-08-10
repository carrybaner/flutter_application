import 'dart:io';
import '../models/protocol_item.dart';

/// 纯 CSV 配置导出/导入服务
class ConfigExportService {
  ConfigExportService._();

  // ──────── 导出 ────────

  /// 生成 CSV 文本（显示值）
  ///
  /// [values] 与 [writableGroups] 一一对应，每个 List<dynamic> 与 group.fields 一一对应
  static String buildExportCsv({
    required String protocolId,
    required List<ProtocolGroup> writableGroups,
    required List<List<dynamic>> values,
  }) {
    final buf = StringBuffer();
    buf.writeln('Target Model,$protocolId');
    buf.writeln('name,Value');
    buf.writeln();

    for (int gIdx = 0; gIdx < writableGroups.length; gIdx++) {
      final group = writableGroups[gIdx];
      final groupValues = values[gIdx];

      buf.writeln('# ${group.groupCode}');
      for (int fIdx = 0; fIdx < group.fields.length; fIdx++) {
        final field = group.fields[fIdx];
        final raw = groupValues[fIdx];
        final display = _formatCsvValue(raw);
        buf.writeln('${field.nameEnglish ?? ''},$display');
      }
      buf.writeln(); // 组间空行
    }

    return buf.toString();
  }

  /// 格式化单个值为 CSV 友好的字符串（显示值）
  static String _formatCsvValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value; // HEX 类型 "0x0000"
    if (value is num) {
      final d = value.toDouble();
      // 整数或接近整数 → 直接输出整数
      if ((d - d.roundToDouble()).abs() < 1e-9) {
        return d.round().toString();
      }
      // 浮点数：保留合理精度，去掉尾零
      var s = d.toStringAsFixed(9);
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return s;
    }
    return value.toString();
  }

  /// 导出 CSV 到文件（自动命名：{protocolId}_{timestamp}.csv）
  static Future<File> exportToFile(String csvContent, String protocolId) async {
    final dir = await _configDirectory();
    final timestamp = DateTime.now()
        .toLocal()
        .toString()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final fileName = '${protocolId}_$timestamp.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvContent);
    return file;
  }

  /// 以自定义文件名导出 CSV 到配置目录
  static Future<File> exportToFileWithName(String csvContent, String fileName) async {
    final dir = await _configDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvContent);
    return file;
  }

  // ──────── 导入 ────────

  /// 从 CSV 文件导入配置
  static Future<CsvImportResult> importFromFile(File file) async {
    final content = await file.readAsString();
    return _parseCsv(content);
  }

  /// 解析 CSV 文本
  static CsvImportResult _parseCsv(String csv) {
    final lines = csv.split(RegExp(r'\r?\n'));
    if (lines.length < 2) {
      return CsvImportResult(success: false, error: 'CSV 文件格式无效（行数不足）');
    }

    // 第 1 行: Target Model,{protocolId}
    String protocolId = '';
    final firstLine = lines[0].trim();
    final targetMatch = RegExp(r'^Target\s*Model\s*[,;]\s*(.+)$', caseSensitive: false)
        .firstMatch(firstLine);
    if (targetMatch != null) {
      protocolId = targetMatch.group(1)!.trim();
    }

    // 第 2 行: name,Value（跳过）
    // 后续行: 解析 # groupCode 和 name,value
    final groupData = <String, Map<String, String>>{};
    String? currentGroup;
    int lineNum = 1;

    for (int i = 2; i < lines.length; i++) {
      lineNum = i + 1;
      final line = lines[i].trim();

      // 跳过空行
      if (line.isEmpty) continue;

      // 组标记: # groupCode
      if (line.startsWith('#')) {
        currentGroup = line.substring(1).trim();
        if (currentGroup.isEmpty) {
          return CsvImportResult(
            success: false,
            error: '第 $lineNum 行：# 后缺少组名',
          );
        }
        groupData.putIfAbsent(currentGroup, () => <String, String>{});
        continue;
      }

      // 参数行: name,value
      if (currentGroup == null) {
        // 没有组标记的行跳过（可能是旧格式的 Target Model 之后直接跟参数）
        // 但如果整个文件都没有 # 标记，则报错
        continue;
      }

      final commaIdx = line.indexOf(',');
      if (commaIdx < 0) continue; // 跳过无法解析的行

      final name = line.substring(0, commaIdx).trim();
      final value = line.substring(commaIdx + 1).trim();
      if (name.isNotEmpty) {
        groupData[currentGroup]![name] = value;
      }
    }

    if (groupData.isEmpty) {
      return CsvImportResult(
        success: false,
        error: 'CSV 文件中未找到有效的参数数据。请确认文件包含 # groupCode 标记行。',
      );
    }

    // 检查是否所有组都没有 # 标记（旧格式）
    if (protocolId.isEmpty) {
      return CsvImportResult(
        success: false,
        error: 'CSV 第 1 行缺少 "Target Model,{型号}" 信息',
      );
    }

    return CsvImportResult(
      success: true,
      protocolId: protocolId,
      groupData: groupData,
    );
  }

  /// 列出已保存的 CSV 配置文件
  static Future<List<File>> listSavedConfigs() async {
    final dir = await _configDirectory();
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.csv'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  /// 获取配置目录
  static Future<Directory> _configDirectory() async {
    // 尝试多个可能的目录
    final candidates = <String>[
      '/storage/emulated/0/Download/bms_configs', // Android 下载目录
      '${_homePath()}/Downloads/bms_configs',
      '${_homePath()}/bms_configs',
      './bms_configs',
    ];

    for (final path in candidates) {
      try {
        final dir = Directory(path);
        // 尝试创建以验证可写
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        // 测试写入
        final testFile = File('${dir.path}/.write_test');
        await testFile.writeAsString('test');
        await testFile.delete();
        return dir;
      } catch (_) {
        continue;
      }
    }

    // 最终降级到当前目录
    final fallback = Directory('./bms_configs');
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }

  static String _homePath() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return home;
  }

  /// 将外部文件复制到配置目录，返回复制后的文件
  static Future<File> copyToConfigDir(File sourceFile, String protocolId) async {
    final dir = await _configDirectory();
    final timestamp = DateTime.now()
        .toLocal()
        .toString()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final fileName = '${protocolId}_$timestamp.csv';
    final destFile = File('${dir.path}/$fileName');
    await sourceFile.copy(destFile.path);
    return destFile;
  }

  /// 从外部文件导入配置（验证并复制到配置目录）
  /// 返回 null 表示成功，返回错误信息字符串表示失败
  static Future<String?> importExternalFile(File sourceFile) async {
    // 1. 验证文件是否为 CSV 格式
    try {
      final content = await sourceFile.readAsString();
      final result = _parseCsv(content);
      if (!result.success) {
        return result.error ?? 'CSV 解析失败';
      }
      // 2. 复制到配置目录
      await copyToConfigDir(sourceFile, result.protocolId);
      return null; // 成功
    } catch (e) {
      return '读取文件失败: $e';
    }
  }
}

// ──────── 导入结果 ────────

class CsvImportResult {
  final bool success;
  final String? error;
  final String protocolId;

  /// {groupCode: {nameEnglish: csvValue}}
  final Map<String, Map<String, String>> groupData;

  CsvImportResult({
    required this.success,
    this.error,
    this.protocolId = '',
    this.groupData = const {},
  });

  /// CSV 中的参数总数
  int get totalFieldCount =>
      groupData.values.fold(0, (sum, m) => sum + m.length);

  /// CSV 中的组数
  int get groupCount => groupData.length;
}
