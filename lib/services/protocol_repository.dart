import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/protocol_item.dart';

/// 协议数据库加载器 — 从 assets/protocols/ 加载 JSON
class ProtocolRepository {
  ProtocolRepository._();
  static final ProtocolRepository instance = ProtocolRepository._();

  static const _assetPath = 'assets/protocols';

  // ============================================================
  // 加载型号索引
  // ============================================================

  /// 加载 index.json
  Future<Map<String, Map<String, dynamic>>> loadIndex() async {
    final json = await _readJsonFile('$_assetPath/index.json');
    if (json == null) return {};

    final index = <String, Map<String, dynamic>>{};
    for (final entry in (json as Map<String, dynamic>).entries) {
      index[entry.key] = entry.value as Map<String, dynamic>;
    }
    return index;
  }

  /// 加载指定 protocolId 的完整协议定义
  /// 支持两种文件名格式: DC24S_{id}.json 或 {id}.json
  Future<ProtocolDataBundle?> loadProtocol(String protocolId) async {
    // 先尝试 DC24S_ 前缀，再尝试直接 ID
    dynamic json = await _readJsonFile('$_assetPath/DC24S_$protocolId.json');
    json ??= await _readJsonFile('$_assetPath/$protocolId.json');
    if (json == null) return null;

    // 格式A: {"groups": [...]}
    if (json is Map<String, dynamic> && json['groups'] != null) {
      return ProtocolDataBundle.fromJson(json, protocolId);
    }

    // 格式B: 扁平数组 [...]
    if (json is List) {
      return _parseFlatArray(json, protocolId);
    }

    return null;
  }

  /// 解析扁平数组格式：按 Show=FALSE 切分为多个组
  ProtocolDataBundle _parseFlatArray(
      List<dynamic> rawItems, String protocolId) {
    final groups = <ProtocolGroup>[];
    List<ProtocolItem>? currentItems;
    String? currentName;

    for (final raw in rawItems) {
      final item = ProtocolItem.fromJson(raw as Map<String, dynamic>);

      if (!item.show && item.code != null) {
        // 新的 header 行 → 保存上一组，开始新组
        if (currentItems != null && currentName != null) {
          final ct = currentItems.first.configType ?? 'Register';
          final chName = currentItems
                  .expand((i) => [i.configNameChinese])
                  .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => currentName) ??
              currentName;
          final enName = currentItems
                  .expand((i) => [i.configNameEnglish])
                  .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => currentName) ??
              currentName;
          groups.add(ProtocolGroup(
            groupCode: currentName,
            chineseName: chName,
            englishName: enName,
            configType: ct,
            items: List.unmodifiable(currentItems),
          ));
        }
        currentItems = [item];
        currentName = null; // 重置，等下一个字段行设定新组名
      } else {
        // 数据行
        currentItems?.add(item);
        if (currentName == null) {
          currentName = item.configNameEnglish ??
              item.nameEnglish ??
              item.nameChinese ??
              'Unknown';
        }
      }
    }

    // 最后一组
    if (currentItems != null && currentItems.length > 1 && currentName != null) {
      final ct = currentItems.first.configType ?? 'Register';
      final chineseName = currentItems
              .expand((i) => [i.configNameChinese])
              .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => currentName) ??
          currentName;
      final englishName = currentItems
              .expand((i) => [i.configNameEnglish])
              .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => currentName) ??
          currentName;
      groups.add(ProtocolGroup(
        groupCode: currentName,
        chineseName: chineseName,
        englishName: englishName,
        configType: ct,
        items: List.unmodifiable(currentItems),
      ));
    }

    return ProtocolDataBundle(
      protocolId: protocolId,
      modelName: '',
      description: '',
      groups: groups,
    );
  }

  // ============================================================
  // 内部
  // ============================================================

  Future<dynamic> _readJsonFile(String path) async {
    try {
      final content = await rootBundle.loadString(path);
      return json.decode(content);
    } catch (e) {
      return null;
    }
  }
}

/// 协议数据包
class ProtocolDataBundle {
  final String protocolId;
  final String modelName;
  final String description;
  final List<ProtocolGroup> groups;

  const ProtocolDataBundle({
    required this.protocolId,
    required this.modelName,
    required this.description,
    required this.groups,
  });

  /// 实时数据组（连接后持续轮询）— configType == "Register"
  List<ProtocolGroup> get realtimeGroups =>
      groups.where((g) => g.configType == 'Register').toList();

  /// 可写参数组（进入参数设置 Tab 后按需读取）— configType == "Data Memery"
  List<ProtocolGroup> get writableGroups =>
      groups.where((g) => g.configType == 'Data Memery').toList();

  /// 异常记录组
  List<ProtocolGroup> get historyGroups =>
      groups.where((g) => g.configType == 'Calendar').toList();

  /// 按 groupCode 查找
  ProtocolGroup? findByCode(String groupCode) {
    try {
      return groups.firstWhere((g) => g.groupCode == groupCode);
    } catch (_) {
      return null;
    }
  }

  factory ProtocolDataBundle.fromJson(
      Map<String, dynamic> json, String protocolId) {
    return ProtocolDataBundle(
      protocolId: protocolId,
      modelName: json['modelName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      groups: (json['groups'] as List<dynamic>)
          .map((e) => ProtocolGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
