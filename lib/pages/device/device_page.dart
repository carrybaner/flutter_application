import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/device_model.dart';
import '../../providers/device_data_provider.dart'
    show realtimeDataProvider, isConnectedProvider, realtimePollerProvider;
import '../../providers/theme_provider.dart';
import '../../services/bluetooth_service.dart';
import '../../services/command_builder.dart';
import '../../i18n/app_strings.dart';
import '../../i18n/locale_provider.dart';
import 'tabs/battery_info_tab.dart';
import 'tabs/param_setting_tab.dart';
import 'tabs/abnormal_record_tab.dart';
import 'tabs/extended_command_tab.dart';

/// 设备详情页 — 四标签切换
class DevicePage extends ConsumerStatefulWidget {
  final DeviceModel device;
  final ConnectionResult connectionResult;
  const DevicePage({
    super.key,
    required this.device,
    required this.connectionResult,
  });

  @override
  ConsumerState<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends ConsumerState<DevicePage>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  AppStrings _s = AppStrings.zh;
  late final AnimationController _indicatorCtrl;

  List<_TabInfo> get _tabs => [
    _TabInfo(icon: Icons.battery_full, label: _s.device.battery),
    _TabInfo(icon: Icons.tune, label: _s.device.params),
    _TabInfo(icon: Icons.warning_amber, label: _s.device.records),
    _TabInfo(icon: Icons.extension, label: _s.device.commands),
  ];

  @override
  void initState() {
    super.initState();
    _indicatorCtrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _indicatorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _s = ref.watch(localeProvider);
    final adv = widget.device.advData;

    // 监听断连
    ref.listen<bool>(isConnectedProvider, (prev, next) {
      if (prev == true && next == false) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(_s.device.disconnected),
            content: Text(_s.device.disconnectedDesc),
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          Navigator.of(context).pop(); // 关闭弹窗
          Navigator.of(context).pop(); // 返回扫描页
        });
      }
    });

    // 从实时轮询数据读取 SOC，与仪表盘同步
    final data = ref.watch(realtimeDataProvider);
    final batteryInfo = data['BatteryInfo'];
    final realtimeSoc = (batteryInfo?['SOC'] as num?)?.toInt()
        ?? (adv.isValid ? adv.soc : 0);

    return Scaffold(
      appBar: _buildAppBar(isDark, realtimeSoc),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          const BatteryInfoTab(),
          ParamSettingTab(isActive: _selectedTab == 1),
          AbnormalRecordTab(isActive: _selectedTab == 2),
          const ExtendedCommandTab(),
        ],
      ),
      bottomNavigationBar: _buildTabBar(isDark),
    );
  }

  // ──── 修改 SN 码（仅 7030 协议）────

  /// 点击顶部 SN/已连接 区域：仅 7030 协议支持，其余无反应
  void _handleSnTap() {
    if (widget.connectionResult.protocolId != '7030') return;
    _showModifySnDialog();
  }

  /// 修改 SN 码对话框
  void _showModifySnDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.edit_note, color: Colors.blue, size: 22),
          const SizedBox(width: 8),
          Text(_s.device.modifySn),
        ]),
        content: TextField(
          controller: controller,
          maxLength: 13,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _s.device.modifySnHint,
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_s.common.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final sn = controller.text.trim();
              if (!_isValidSn(sn)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_s.device.modifySnInvalid)),
                );
                return;
              }
              Navigator.pop(ctx);
              _executeModifySn(sn);
            },
            child: Text(_s.common.ok),
          ),
        ],
      ),
    );
  }

  /// SN 校验：13 位且字符为可打印 ASCII（32~126）
  bool _isValidSn(String sn) =>
      sn.length == 13 && sn.codeUnits.every((c) => c >= 32 && c <= 126);

  /// 发送修改 SN → 成功自动重启 BMS（设备断开由断连监听自动返回列表）
  Future<void> _executeModifySn(String sn) async {
    // 加载动画
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              Text(_s.device.modifySnSending),
            ],
          ),
        ),
      ),
    );

    final poller = ref.read(realtimePollerProvider);
    if (poller == null || !mounted) return;

    try {
      // 1. 发送修改 SN 命令，等设备响应
      final resp = await poller
          .sendAndWaitResponse(CommandBuilder.buildModifySnCommand(sn));
      if (resp == null) {
        if (mounted) _showSnack(_s.device.modifySnFailed);
        return;
      }
      // 2. 修改成功 → 自动发送重启 BMS 命令（设备重启断开）
      await poller
          .sendAndWaitResponse(CommandBuilder.buildRestartBmsCommand());
    } catch (_) {
      // 忽略：重启命令发送异常（设备可能已断开），由断连监听返回
    } finally {
      // 关闭加载动画，断开返回由现有断连监听完成
      if (mounted) _closeLoadingDialog();
    }
  }

  void _closeLoadingDialog() {
    Navigator.of(context).pop();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark, int soc) {

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        onTap: _handleSnTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.device.displayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            _StatusBadge(label: _s.device.connected),
          ],
        ),
      ),
      actions: [
        // 主题切换
        IconButton(
          icon: Icon(
            isDark ? Icons.light_mode : Icons.dark_mode,
            size: 20,
          ),
          onPressed: () => ref.read(themeProvider.notifier).toggle(),
        ),
        // 迷你电量胶囊
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _MiniSocCapsule(soc: soc),
        ),
      ],
    );
  }

  Widget _buildTabBar(bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabWidth = MediaQuery.of(context).size.width / 4;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surface
            : Colors.white,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Stack(
            children: [
              // 高亮指示条
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                left: _selectedTab * tabWidth + 12,
                top: 0,
                child: Container(
                  width: tabWidth - 24,
                  height: 3,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(2),
                    ),
                  ),
                ),
              ),

              // Tab 按钮
              Row(
                children: List.generate(_tabs.length, (i) {
                  final isSelected = _selectedTab == i;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selectedTab = i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _tabs[i].icon,
                            size: 22,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _tabs[i].label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "已连接" 状态小标签
class _StatusBadge extends StatelessWidget {
  final String label;
  const _StatusBadge({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 迷你电量胶囊
class _MiniSocCapsule extends StatelessWidget {
  final int soc;
  const _MiniSocCapsule({required this.soc});

  Color get _color {
    if (soc > 60) return Colors.green;
    if (soc > 20) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: _color.withOpacity(0.12),
        border: Border.all(color: _color.withOpacity(0.5), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.battery_charging_full, size: 12, color: _color),
          const SizedBox(width: 3),
          Text(
            '$soc%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab 信息
class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo({required this.icon, required this.label});
}
