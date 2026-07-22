import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/param_group.dart';
import '../../../models/protocol_item.dart';
import '../../../providers/device_data_provider.dart';
import '../../../services/bluetooth_service.dart';
import '../../../services/command_builder.dart';
import '../../../services/protocol_parser.dart';
import '../../../theme/app_theme.dart';
import '../widgets/param_input_field.dart';

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
    if (_lastResult != currentResult) {
      _lastResult = currentResult;
      _loaded = false;
      _groups = [];
      _values = [];
      _loading = true;
      if (widget.isActive) _tryLoad();
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_groups.isEmpty) {
      return const Center(child: Text('无可用参数', style: TextStyle(color: Colors.grey)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
      children: [
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
                  _onWrite(_groups[_selectedCategory], i, newVal);
                },
              );
            },
          ),
        ),
      ],
    ));
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
                _groups[i].chineseName,
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

  Future<void> _onWrite(ProtocolGroup group, int fieldIndex, double newValue) async {
    final field = group.fields[fieldIndex];
    final name = field.nameChinese ?? field.nameEnglish ?? '';

    // 确认弹窗
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 24),
          SizedBox(width: 8),
          Text('确认修改'),
        ]),
        content: Text('$name\n新值: $newValue',
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Length=1 配对处理：取相邻字段原始值
    final groupIdx = _groups.indexOf(group);
    dynamic pairedValue;
    if (field.length == 1 && groupIdx >= 0) {
      final pairIdx = (fieldIndex % 2 == 0) ? fieldIndex + 1 : fieldIndex - 1;
      if (pairIdx < _values[groupIdx].length) {
        pairedValue = _values[groupIdx][pairIdx];
      }
      if (pairedValue == null) {
        _showSnackBar('配对字段值缺失，无法写入');
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
      _showSnackBar('命令构建失败');
      return;
    }
    final hex = await poller.sendAndWaitResponse(cmd);

    if (!mounted) return;
    // 写入指令设备可能不回复 notify，超时≠失败
    final success = hex != null;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            success ? Icons.check_circle : Icons.warning_amber,
            color: success ? Colors.green : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(success ? '修改成功' : '已下发，等待生效'),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
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
      name: field.nameChinese ?? field.nameEnglish ?? '',
      unit: field.unit ?? '',
      currentValue: displayValue,
      displayText: displayText,
      minValue: 0,
      maxValue: 99999,
    );
  }

}
