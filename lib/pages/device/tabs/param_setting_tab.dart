import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/param_group.dart';
import '../../../i18n/app_strings.dart';
import '../../../i18n/locale_provider.dart';
import '../../../models/protocol_item.dart';
import '../../../providers/device_data_provider.dart';
import '../../../services/bluetooth_service.dart';
import '../../../services/command_builder.dart';
import '../../../services/config_export_service.dart';
import '../../../services/protocol_parser.dart';
import '../../../services/realtime_poller.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirmation_dialog.dart';
import '../widgets/param_input_field.dart';

/// 参数修改日志条目（会话级，断开设备后清空）
class _ModificationLogEntry {
  final DateTime timestamp;
  final ProtocolGroup group;
  final int fieldIndex;
  final double oldValue;
  final double newValue;
  final String paramName;
  final String unit;
  final String oldDisplay;
  final String newDisplay;
  bool undone;

  _ModificationLogEntry({
    required this.timestamp,
    required this.group,
    required this.fieldIndex,
    required this.oldValue,
    required this.newValue,
    required this.paramName,
    required this.unit,
    required this.oldDisplay,
    required this.newDisplay,
  }) : undone = false;
}

/// 批量写入任务
class _BatchWriteTask {
  final ProtocolGroup group;
  final List<dynamic> values;
  final int startFieldIndex;
  final int endFieldIndex; // exclusive
  final bool perField; // 逐字段写入（含 r 的组）
  _BatchWriteTask({required this.group, required this.values, this.startFieldIndex = 0, this.endFieldIndex = -1, this.perField = false});
  int get actualEnd => endFieldIndex < 0 ? group.fields.length : endFieldIndex;
}

/// 参数设置 Tab — 首次激活时逐组加载所有可写参数
class ParamSettingTab extends ConsumerStatefulWidget {
  final bool isActive;
  const ParamSettingTab({super.key, this.isActive = false});

  @override
  ConsumerState<ParamSettingTab> createState() => _ParamSettingTabState();
}

class _ParamSettingTabState extends ConsumerState<ParamSettingTab> {
  int _selectedCategory = 0;
  List<ProtocolGroup> _groups = [];
  List<List<dynamic>> _values = [];
  bool _loading = true;
  bool _loaded = false;
  ConnectionResult? _lastResult;
  AppStrings _s = AppStrings.zh;
  final List<_ModificationLogEntry> _modificationLogs = [];

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _tryLoad();
  }

  @override
  void didUpdateWidget(ParamSettingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) _tryLoad();
  }

  void _tryLoad() {
    if (_loaded) return;
    _loaded = true;
    _loadAllParams();
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _loadAllParams() async {
    final bundle = ref.read(connectionResultProvider)?.bundle;
    if (bundle == null) return;

    final writableGroups = bundle.writableGroups;
    final poller = ref.read(realtimePollerProvider);

    // 已有缓存直接用（poller 未重启时 cache 仍保留）
    if (poller != null &&
        writableGroups.every((g) => poller.cache.containsKey(g.groupCode))) {
      // 已有缓存，直接用
      final loadedGroups = <ProtocolGroup>[];
      final loadedValues = <List<dynamic>>[];
      for (final group in writableGroups) {
        final map = poller.cache[group.groupCode]!;
        final list = group.fields.map((f) => map[f.nameEnglish]).toList();
        loadedGroups.add(group);
        loadedValues.add(list);
      }
      if (mounted) {
        setState(() {
          _groups = loadedGroups;
          _values = loadedValues;
          _loading = false;
        });
      }
      return;
    }

    if (poller == null) return;

    final loadedGroups = <ProtocolGroup>[];
    final loadedValues = <List<dynamic>>[];

    for (final group in writableGroups) {
      try {
        final cmd = CommandBuilder.buildReadCommand(group);
        final hex = await poller.sendAndWaitResponse(cmd);
        if (hex == null) continue;

        final values = ProtocolParser.parseToList(group, hex);
        if (values == null) continue;

        loadedGroups.add(group);
        loadedValues.add(values);

        // 缓存供 Length=1 配对写入使用
        final parsedMap = ProtocolParser.parseToMap(group, hex);
        if (parsedMap != null) {
          poller.cache[group.groupCode] = parsedMap;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _groups = loadedGroups;
        _values = loadedValues;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 检测设备切换，重置加载状态
    final currentResult = ref.watch(connectionResultProvider);
    _s = ref.watch(localeProvider);
    if (_lastResult != currentResult) {
      _lastResult = currentResult;
      _loaded = false;
      _groups = [];
      _values = [];
      _loading = true;
      _modificationLogs.clear();
      if (widget.isActive) _tryLoad();
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_groups.isEmpty) {
      return Center(child: Text(_s.param.noData, style: const TextStyle(color: Colors.grey)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
      children: [
        _buildActionButtons(isDark),
        _buildCategoryBar(isDark),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _selectedCategory < _groups.length
                ? _groups[_selectedCategory].fields.length
                : 0,
            itemBuilder: (_, i) {
              final field = _groups[_selectedCategory].fields[i];
              final value = _values[_selectedCategory][i];
              return ParamInputField(
                param: _toParamItem(field, value),
                onChanged: (oldVal, newVal) {
                  _onWrite(_groups[_selectedCategory], i, oldVal, newVal);
                },
              );
            },
          ),
        ),
      ],
    ));
  }

  Widget _buildActionButtons(bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildBtn(String label, IconData icon, {VoidCallback? onPressed}) => OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.4),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          buildBtn(_s.param.oneKeyConfig, Icons.auto_fix_high, onPressed: _quickConfig),
          const SizedBox(width: 10),
          buildBtn(_s.param.exportConfig, Icons.download, onPressed: _exportConfig),
          const Spacer(),
          buildBtn(_s.param.log, Icons.article_outlined, onPressed: _showLogSheet),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(bool isDark) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _groups.length,
        itemBuilder: (_, i) {
          final sel = _selectedCategory == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              decoration: BoxDecoration(
                color: sel
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: sel
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary, width: 0.5)
                    : null,
              ),
              child: Text(
                _s.protocolField(_groups[i].chineseName, _groups[i].englishName.isEmpty ? _groups[i].chineseName : _groups[i].englishName),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────── 日志弹窗 ────────

  void _showLogSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            expand: false,
            builder: (_, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Spacer(),
                      Text(_s.param.log, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      const SizedBox(width: 36),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _modificationLogs.isEmpty
                      ? Center(
                          child: Text(
                            _s.param.noData,
                            style: const TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _modificationLogs.length,
                          itemBuilder: (_, i) {
                            final entry = _modificationLogs[i];
                            final timeStr =
                                '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                                '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                                '${entry.timestamp.second.toString().padLeft(2, '0')}';
                            final cs = Theme.of(context).colorScheme;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.paramName,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: entry.undone ? Colors.grey : cs.onSurface,
                                              decoration: entry.undone ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${entry.oldDisplay}${entry.unit.isNotEmpty ? " ${entry.unit}" : ""} → '
                                            '${entry.newDisplay}${entry.unit.isNotEmpty ? " ${entry.unit}" : ""}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: entry.undone ? Colors.grey : cs.onSurfaceVariant,
                                              decoration: entry.undone ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                        ],
                                      ),
                                    ),
                                    if (entry.undone)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Text(_s.param.writeSuccessShort, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                      )
                                    else
                                      TextButton.icon(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _undoModification(entry);
                                        },
                                        icon: const Icon(Icons.undo, size: 16),
                                        label: Text(_s.param.writeConfirmShort, style: const TextStyle(fontSize: 13)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────── 导出配置 ────────

  Future<void> _exportConfig() async {
    final bundle = ref.read(connectionResultProvider)?.bundle;
    if (bundle == null) {
      _showSnackBar(_s.command.notConnected);
      return;
    }

    final writableGroups = bundle.writableGroups;
    final poller = ref.read(realtimePollerProvider);

    // 收集所有可写组的当前值（显示值，优先从缓存取）
    final exportedGroups = <ProtocolGroup>[];
    final allValues = <List<dynamic>>[];
    final skippedGroups = <String>[];
    for (final group in writableGroups) {
      if (poller != null && poller.cache.containsKey(group.groupCode)) {
        final map = poller.cache[group.groupCode]!;
        exportedGroups.add(group);
        allValues.add(group.fields.map((f) => map[f.nameEnglish]).toList());
      } else if (poller != null) {
        // 缓存未命中，从设备读取
        bool readOk = false;
        try {
          final cmd = CommandBuilder.buildReadCommand(group);
          final hex = await poller.sendAndWaitResponse(cmd);
          if (hex != null) {
            final values = ProtocolParser.parseToList(group, hex);
            if (values != null) {
              exportedGroups.add(group);
              allValues.add(values);
              final parsedMap = ProtocolParser.parseToMap(group, hex);
              if (parsedMap != null) poller.cache[group.groupCode] = parsedMap;
              readOk = true;
            }
          }
        } catch (_) {}
        if (!readOk) {
          skippedGroups.add(group.groupCode);
        }
      } else {
        _showSnackBar(_s.command.notConnected);
        return;
      }
    }

    if (exportedGroups.isEmpty) {
      _showSnackBar(_s.param.noData);
      return;
    }

    final csv = ConfigExportService.buildExportCsv(
      protocolId: bundle.protocolId,
      writableGroups: exportedGroups,
      values: allValues,
    );

    // 弹出命名对话框
    final fileName = await _showExportNameDialog(bundle.protocolId);
    if (fileName == null || !mounted) return;

    try {
      final file = await ConfigExportService.exportToFileWithName(csv, fileName);
      if (!mounted) return;
      final skippedText = skippedGroups.isNotEmpty
          ? '\n跳过: ${skippedGroups.join(', ')}（设备未响应）'
          : '';
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            Text(_s.param.exportConfig),
          ]),
          content: Text('${file.path}$skippedText', style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_s.common.ok),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnackBar('${_s.param.writeFail}: $e');
    }
  }

  /// 导出文件命名对话框，返回完整文件名（含 .csv 后缀）
  Future<String?> _showExportNameDialog(String protocolId) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_s.param.exportConfig),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_s.param.exportFileName,
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                border: UnderlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_s.common.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final input = controller.text.trim();
              final now = DateTime.now();
              final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
              final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
              final fileName = '${input}_${protocolId}_${dateStr}_$timeStr.csv';
              Navigator.pop(context, fileName);
            },
            child: Text(_s.common.ok),
          ),
        ],
      ),
    );
  }

  // ──────── 一键配置 ────────

  Future<void> _quickConfig() async {
    final bundle = ref.read(connectionResultProvider)?.bundle;
    if (bundle == null) {
      _showSnackBar(_s.command.notConnected);
      return;
    }

    // 列出已保存的 CSV 配置文件，仅显示匹配当前产品型号的文件
    final allFiles = await ConfigExportService.listSavedConfigs();
    final files = allFiles
        .where((f) => f.path.contains(bundle.protocolId))
        .toList();

    if (!mounted) return;
    final selectedFile = await showModalBottomSheet<File>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (_, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    Text(_s.param.oneKeyConfig,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: files.isEmpty
                    ? Center(
                        child: Text(_s.param.noMatchingConfig.replaceAll('%s', bundle.protocolId),
                            style: const TextStyle(color: Colors.grey, fontSize: 15)))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: files.length,
                        itemBuilder: (_, i) {
                          final f = files[i];
                          final name = f.uri.pathSegments.last;
                          final size = f.lengthSync();
                          final date = f.lastModifiedSync();
                          final dateStr =
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
                              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                          return ListTile(
                            leading: const Icon(Icons.description, color: Colors.blue),
                            title: Text(name, style: const TextStyle(fontSize: 14)),
                            subtitle: Text('$dateStr  ${(size / 1024).toStringAsFixed(1)} KB',
                                style: const TextStyle(fontSize: 12)),
                            onTap: () => Navigator.pop(context, f),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedFile == null) return;

    // 解析 CSV
    final result = await ConfigExportService.importFromFile(selectedFile);
    if (!result.success) {
      if (!mounted) return;
      _showSnackBar(result.error ?? _s.param.writeFail);
      return;
    }

    // 协议 ID 验证
    if (result.protocolId != bundle.protocolId) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Text(_s.param.oneKeyConfig),
          ]),
          content: Text(
            '配置文件协议 ${result.protocolId} 与当前设备协议 ${bundle.protocolId} 不匹配，\n'
            '继续写入可能导致异常。是否继续？',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_s.common.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_s.common.ok),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    _doBatchWrite(result, bundle.writableGroups);
  }

  // ──────── 批量写入 ────────

  Future<void> _doBatchWrite(
    CsvImportResult result,
    List<ProtocolGroup> writableGroups,
  ) async {
    // 构建 groupCode → ProtocolGroup 索引
    final groupMap = <String, ProtocolGroup>{};
    for (final g in writableGroups) {
      groupMap[g.groupCode] = g;
    }

    // 收集待写入的任务: (ProtocolGroup, List<dynamic> values)
    final tasks = <_BatchWriteTask>[];
    final unmatchedNames = <String>[]; // CSV 中有但协议中没有的组
    final skippedReadonly = <String>[]; // 被跳过的只读字段
    for (final entry in result.groupData.entries) {
      final csvGroupCode = entry.key;
      final csvFields = entry.value;
      final group = groupMap[csvGroupCode];
      if (group == null) {
        unmatchedNames.add(csvGroupCode);
        continue;
      }

      // 按 group.fields 顺序构建值数组（写入用，数值用 double，HEX 保留 String）
      final values = <dynamic>[];
      for (final field in group.fields) {
        final csvValue = csvFields[field.nameEnglish];
        if (csvValue == null) {
          values.add(0);
          continue;
        }
        values.add(_parseCsvValue(csvValue, field));
      }

      // 判断组内是否有 r 字段
      final hasReadOnly = group.fields.any((f) => f.type == 'r');

      if (hasReadOnly) {
        // 有 r 字段 → 标记为逐字段写入
        tasks.add(_BatchWriteTask(group: group, values: values, perField: true));
      } else if (csvGroupCode == 'EDV Table') {
        // EDV Table 特殊处理：拆分为 前10 + 剩余 两条命令
        tasks.add(_BatchWriteTask(group: group, values: values, startFieldIndex: 0, endFieldIndex: 10));
        tasks.add(_BatchWriteTask(group: group, values: values, startFieldIndex: 10));
      } else {
        tasks.add(_BatchWriteTask(group: group, values: values));
      }
    }

    if (tasks.isEmpty) {
      if (!mounted) return;
      final extra = unmatchedNames.isNotEmpty
          ? '\n\n未识别的组: ${unmatchedNames.join(', ')}'
          : '';
      _showSnackBar('CSV 中没有与当前设备匹配的可写参数组。$extra');
      return;
    }

    // 进度弹窗
    int successCount = 0;
    int failCount = 0;
    final totalGroups = tasks.length;
    final progressNotifier = ValueNotifier<int>(0);

    if (!mounted) return;
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: progressNotifier,
        builder: (_, done, __) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text('正在写入 $done / $totalGroups',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('成功 $successCount  失败 $failCount',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    final poller = ref.read(realtimePollerProvider);

    int taskIdx = 0;
    for (final task in tasks) {
      taskIdx++;

      if (poller == null) {
        failCount++;
        progressNotifier.value++;
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      if (task.perField) {
        final (ok, fail) = await _writePerField(task, poller);
        if (fail == 0) successCount++; else failCount++;
      } else {
        String cmd;
        try {
          cmd = CommandBuilder.buildGroupWriteCommand(task.group, task.values,
              startFieldIndex: task.startFieldIndex,
              endFieldIndex: task.actualEnd);
        } catch (_) {
          failCount++;
          progressNotifier.value++;
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        if (cmd.isEmpty) {
          failCount++;
          progressNotifier.value++;
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        try {
          final hex = await poller.sendAndWaitResponse(cmd);
          if (hex != null) {
            successCount++;
          } else {
            failCount++;
          }
        } catch (_) {
          failCount++;
        }
      }
      progressNotifier.value++;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    progressNotifier.dispose();

    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭进度弹窗

    // 汇总
    final summaryParts = <String>['成功 $successCount 组，失败 $failCount 组'];
    if (unmatchedNames.isNotEmpty) {
      summaryParts.add('CSV 中存在但设备不支持的组: ${unmatchedNames.join(', ')}');
    }

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            failCount == 0 ? Icons.check_circle : Icons.warning_amber,
            color: failCount == 0 ? Colors.green : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(_s.param.oneKeyConfig),
        ]),
        content: Text(summaryParts.join('\n'), style: const TextStyle(fontSize: 14)),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _restartBms();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                child: Text(_s.command.restartBms),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_s.common.ok),
              ),
            ],
          ),
        ],
      ),
    );

    // 写完后清缓存，从设备重新读取全部参数以刷新 UI
    _loaded = false;
    _groups = [];
    _values = [];
    _loading = true;
    poller?.cache.clear();
    _loadAllParams();
  }

  /// 重启 BMS（复用扩展指令页的重启逻辑）
  Future<void> _restartBms() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: _s.command.restartBms,
        message: _s.command.restartConfirm,
        s: _s,
        isDanger: true,
      ),
    );
    if (ok != true || !mounted) return;

    final poller = ref.read(realtimePollerProvider);
    if (poller == null) return;
    try {
      final cmd = CommandBuilder.buildRestartBmsCommand();
      await poller.sendAndWaitResponse(cmd);
      if (mounted) _showSnackBar(_s.command.restartOk);
    } catch (_) {
      if (mounted) _showSnackBar(_s.command.sendFailed);
    }
  }

  /// 逐字段写入（含 r 的组使用此策略）。返回 (ok, fail) 计数。
  Future<(int, int)> _writePerField(
    _BatchWriteTask task,
    RealtimePoller poller,
  ) async {
    final group = task.group;
    final fields = group.fields;
    int fieldOk = 0;
    int fieldFail = 0;

    int i = 0;
    while (i < fields.length) {
      final f = fields[i];
      dynamic pairedValue;
      int pairIdx = -1;

      if (f.length == 1) {
        pairIdx = _findLength1Pair(group, i) ?? -1;
        if (pairIdx >= 0 && pairIdx > i) {
          pairedValue = task.values[pairIdx];
        } else {
          pairedValue = 0;
        }
      }

      try {
        final cmd = CommandBuilder.buildWriteCommand(
          group, i, task.values[i],
          pairedValue: pairedValue,
        );
        if (cmd.isNotEmpty) {
          final hex = await poller.sendAndWaitResponse(cmd);
          if (hex != null) {
            fieldOk++;
          } else {
            fieldFail++;
          }
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (_) {
        fieldFail++;
      }

      if (pairedValue != null) i += 2; else i++;
    }

    return (fieldOk, fieldFail);
  }

  /// 将 CSV 字符串值解析为适合写入的类型
  dynamic _parseCsvValue(String csvValue, ProtocolItem field) {
    // HEX / 2HEX 类型保持字符串
    if (field.dataType == 'HEX' || field.dataType == '2HEX') {
      return csvValue; // 如 "0x0000"
    }
    // 以 0x 开头的值也保持字符串
    if (csvValue.startsWith('0x') || csvValue.startsWith('0X')) {
      return csvValue;
    }
    // 数值类型
    final d = double.tryParse(csvValue);
    if (d != null) return d;
    // 无法解析的返回 0
    return 0;
  }

  /// 根据寄存器偏移找到 Length=1 字段的真正配对（同一寄存器内的另一个字段）
  int? _findLength1Pair(ProtocolGroup group, int fieldIndex) {
    if (fieldIndex < 0 || fieldIndex >= group.fields.length) return null;
    if (group.fields[fieldIndex].length != 1) return null;

    // 计算当前字段所在的寄存器序号
    int targetReg = 0;
    for (int k = 0; k < fieldIndex; k++) {
      targetReg += group.fields[k].length;
    }
    targetReg ~/= 2;

    // 找同一寄存器内的另一个 Length=1 字段
    for (int j = 0; j < group.fields.length; j++) {
      if (j == fieldIndex || group.fields[j].length != 1) continue;
      int regJ = 0;
      for (int k = 0; k < j; k++) {
        regJ += group.fields[k].length;
      }
      regJ ~/= 2;
      if (regJ == targetReg) return j;
    }
    return null;
  }

  // ──────── 撤回 ────────

  Future<void> _undoModification(_ModificationLogEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.undo, color: Colors.orange, size: 24),
          const SizedBox(width: 8),
          Text(_s.param.writeConfirmShort),
        ]),
        content: Text(
          '"${entry.paramName}"\n'
          '${entry.newDisplay}${entry.unit.isNotEmpty ? " ${entry.unit}" : ""} → '
          '${entry.oldDisplay}${entry.unit.isNotEmpty ? " ${entry.unit}" : ""}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_s.common.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_s.param.writeConfirmShort),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final poller = ref.read(realtimePollerProvider);
    if (poller == null) return;

    // 配对处理
    final groupIdx = _groups.indexOf(entry.group);
    final field = entry.group.fields[entry.fieldIndex];
    dynamic pairedValue;
    if (field.length == 1 && groupIdx >= 0) {
      final pairIdx = _findLength1Pair(entry.group, entry.fieldIndex);
      if (pairIdx != null && pairIdx < _values[groupIdx].length) {
        pairedValue = _values[groupIdx][pairIdx];
      }
      if (pairedValue == null) {
        _showSnackBar(_s.param.pairMissing);
        return;
      }
    }

    final cmd = CommandBuilder.buildWriteCommand(
      entry.group, entry.fieldIndex, entry.oldValue,
      pairedValue: pairedValue,
    );
    if (cmd.isEmpty) {
      _showSnackBar(_s.param.cmdBuildFailed);
      return;
    }
    final hex = await poller.sendAndWaitResponse(cmd);

    if (!mounted) return;
    final success = hex != null;
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(
              success ? Icons.check_circle : Icons.warning_amber,
              color: success ? Colors.green : Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(success ? _s.param.writeSuccessShort : _s.param.writeSent),
          ]),
        );
      },
    );

    setState(() => entry.undone = true);

    if (hex != null) {
      _refreshGroup(entry.group);
    } else {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _refreshGroup(entry.group);
      });
    }
  }

  // ──────── 参数写入 ────────

  Future<void> _onWrite(ProtocolGroup group, int fieldIndex, double oldValue, double newValue) async {
    final field = group.fields[fieldIndex];
    final name = _s.protocolField(field.nameChinese, field.nameEnglish);
    final unit = field.unit ?? '';

    // HEX 类型：显示为 0x 格式
    final groupIdx = _groups.indexOf(group);
    final origValue = groupIdx >= 0 ? _values[groupIdx][fieldIndex] : null;
    final isHex = origValue is String && origValue.startsWith('0x');
    String fmtVal(double v) => isHex ? '0x${v.toInt().toRadixString(16).toUpperCase()}' : _formatDisplayValue(v);
    final oldStr = fmtVal(oldValue);
    final newStr = fmtVal(newValue);
    final display = isHex ? '$oldStr → $newStr' : '$oldStr $unit → $newStr $unit';

    // 确认弹窗
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.info_outline, color: Colors.blue, size: 24),
          const SizedBox(width: 8),
          Text(_s.param.writeConfirmShort),
        ]),
        content: Text('"$name"\n$display',
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_s.common.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_s.param.writeConfirmShort),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 记录修改日志
    setState(() {
      _modificationLogs.insert(0, _ModificationLogEntry(
        timestamp: DateTime.now(),
        group: group,
        fieldIndex: fieldIndex,
        oldValue: oldValue,
        newValue: newValue,
        paramName: name,
        unit: unit,
        oldDisplay: oldStr,
        newDisplay: newStr,
      ));
    });

    // Length=1 配对处理：取相邻字段原始值
    dynamic pairedValue;
    if (field.length == 1 && groupIdx >= 0) {
      final pairIdx = _findLength1Pair(group, fieldIndex);
      if (pairIdx != null && pairIdx < _values[groupIdx].length) {
        pairedValue = _values[groupIdx][pairIdx];
      }
      if (pairedValue == null) {
        _showSnackBar(_s.param.pairMissing);
        return;
      }
    }

    final poller = ref.read(realtimePollerProvider);
    if (poller == null) return;

    // buildWriteCommand 内部做反向转换，这里直接传用户输入值
    final cmd = CommandBuilder.buildWriteCommand(
      group, fieldIndex, newValue,
      pairedValue: pairedValue,
    );
    if (cmd.isEmpty) {
      _showSnackBar(_s.param.cmdBuildFailed);
      return;
    }
    final hex = await poller.sendAndWaitResponse(cmd);

    if (!mounted) return;
    // 写入指令设备可能不回复 notify，超时≠失败
    final success = hex != null;
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(
              success ? Icons.check_circle : Icons.warning_amber,
              color: success ? Colors.green : Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(success ? _s.param.writeSuccessShort : _s.param.writeSent),
          ]),
        );
      },
    );

    if (hex != null) {
      _refreshGroup(group);
    } else {
      // 设备不回复 notify，延迟后重读验证
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _refreshGroup(group);
      });
    }
  }

  Future<void> _refreshGroup(ProtocolGroup group) async {
    final poller = ref.read(realtimePollerProvider);
    if (poller == null) return;
    try {
      final cmd = CommandBuilder.buildReadCommand(group);
      final hex = await poller.sendAndWaitResponse(cmd);
      if (hex == null) return;
      final values = ProtocolParser.parseToList(group, hex);
      if (values == null) return;
      final idx = _groups.indexOf(group);
      if (idx >= 0) {
        setState(() => _values[idx] = values);
      }
      final parsedMap = ProtocolParser.parseToMap(group, hex);
      if (parsedMap != null) {
        poller.cache[group.groupCode] = parsedMap;
      }
    } catch (_) {}
  }

  /// 格式化显示值：去掉浮点尾数，与 UI 输入框保持一致
  String _formatDisplayValue(double v) {
    final rounded = v.roundToDouble();
    if ((v - rounded).abs() < 1e-9) return rounded.toInt().toString();
    return v.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  ParamItem _toParamItem(ProtocolItem field, dynamic value) {
    double displayValue;
    String? displayText;
    if (value is num) {
      displayValue = value.toDouble();
    } else if (value is String && value.startsWith('0x')) {
      displayValue = int.tryParse(value.substring(2), radix: 16)?.toDouble() ?? 0;
      displayText = value; // HEX 类型保持原样显示
    } else if (value is String) {
      displayValue = double.tryParse(value) ?? 0;
      displayText = value;
    } else {
      displayValue = 0;
    }
    return ParamItem(
      name: _s.protocolField(field.nameChinese, field.nameEnglish),
      unit: field.unit ?? '',
      currentValue: displayValue,
      displayText: displayText,
      minValue: 0,
      maxValue: 99999,
      readOnly: field.type == 'r',
    );
  }

}
