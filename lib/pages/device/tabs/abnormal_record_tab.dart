import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/abnormal_record.dart';
import '../../../i18n/app_strings.dart';
import '../../../i18n/locale_provider.dart';
import '../../../providers/device_data_provider.dart';
import '../../../services/bluetooth_service.dart';
import '../../../services/command_builder.dart';
import '../../../services/protocol_parser.dart';
import '../widgets/record_card.dart';

/// 异常记录 Tab — 首次激活时发送 64 条独立命令，逐条解析展示
class AbnormalRecordTab extends ConsumerStatefulWidget {
  final bool isActive;
  const AbnormalRecordTab({super.key, this.isActive = false});

  @override
  ConsumerState<AbnormalRecordTab> createState() => _AbnormalRecordTabState();
}

class _AbnormalRecordTabState extends ConsumerState<AbnormalRecordTab> {
  List<AbnormalRecord> _records = [];
  bool _loading = true;
  double _progress = 0.0;
  bool _loaded = false;
  AppStrings _s = AppStrings.zh;
  ConnectionResult? _lastResult;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _tryLoad();
  }

  @override
  void didUpdateWidget(AbnormalRecordTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) _tryLoad();
  }

  void _tryLoad() {
    if (_loaded) return;
    _loaded = true;
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final result = ref.read(connectionResultProvider);
    final bundle = result?.bundle;
    // 缓存命中条件：当前连接与缓存所属连接一致
    final cached = ref.read(recordCacheProvider);
    final cacheOwner = ref.read(recordCacheOwnerProvider);
    if (cached.isNotEmpty && cacheOwner == result?.protocolId) {
      _records = cached;
      if (mounted) setState(() => _loading = false);
      return;
    }

    final poller = ref.read(realtimePollerProvider);
    if (bundle == null || poller == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final historyGroups = bundle.historyGroups;
    if (historyGroups.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final group = historyGroups.first;
    final commands = CommandBuilder.buildReadErrorRecordCommands(group);

    for (int i = 0; i < commands.length; i++) {
      try {
        final hex = await poller.sendAndWaitResponse(commands[i]);
        if (hex == null) continue;

        final values = ProtocolParser.parseToList(group, hex);
        if (values == null || values.isEmpty) continue;

        if (_isValidRecord(values)) {
          _records.add(AbnormalRecord.fromValues(values));
        }
      } catch (_) {}

      // 每5条更新一次进度，减少 setState 调用
      if (mounted && (i % 5 == 0 || i == commands.length - 1)) {
        setState(() => _progress = (i + 1) / commands.length);
      }
    }

    // 按 index 从大到小排序
    _records.sort((a, b) => b.sequenceNumber.compareTo(a.sequenceNumber));
    ref.read(recordCacheProvider.notifier).state = _records;
    ref.read(recordCacheOwnerProvider.notifier).state =
        ref.read(connectionResultProvider)?.protocolId;

    if (mounted) {
      setState(() {
        _loading = false;
        _progress = 1.0;
      });
    }
  }

  bool _isValidRecord(List<dynamic> values) {
    for (final v in values) {
      if (v is num && v != 0) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _s = ref.watch(localeProvider);
    // 检测设备切换，重置加载状态
    final currentResult = ref.watch(connectionResultProvider);
    if (_lastResult != currentResult) {
      _lastResult = currentResult;
      _loaded = false;
      _records = [];
      _loading = true;
      _progress = 0.0;
      if (widget.isActive) _tryLoad();
    }

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_s.record.loading + ' ${(_progress * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: LinearProgressIndicator(value: _progress),
            ),
          ],
        ),
      );
    }

    if (_records.isEmpty) {
      return Center(
        child: Text(_s.record.noRecords, style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      itemBuilder: (_, i) => RecordCard(s: _s, record: _records[i]),
    );
  }
}
