import 'package:flutter/material.dart';
import '../../../models/device_model.dart';
import '../../../models/safety_flags.dart';
import '../../../theme/app_theme.dart';
import 'battery_ring.dart';
import 'rssi_indicator.dart';

/// 设备卡片（胶囊风格）
///
/// 布局：Row 1 — [电量环] [红点+名称] [RSSI]
///       Row 2 — [电量环] [电压+电流+保护状态→]
class DeviceCard extends StatelessWidget {
  final DeviceModel device;
  final VoidCallback? onTap;
  final bool isConnected;

  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
    this.isConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    final adv = device.advData;
    final hasAdv = adv.isValid;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final showFlags = hasAdv &&
        adv.safetyFlags != 0 &&
        adv.safetyFlags != 0xFFFF;
    final activeFlags =
        showFlags ? SafetyFlags.parseRaw(adv.safetyFlags) : <SafetyFlag>[];

    final borderColor = isConnected
        ? Colors.green
        : isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.grey.shade200;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      elevation: isDark ? 0 : 1.5,
      color: isDark ? Theme.of(context).cardTheme.color : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 左侧：电量环 ──
              BatteryRing(
                soc: hasAdv ? adv.soc : -1,
                size: 56,
              ),
              const SizedBox(width: 14),

              // ── 右侧内容 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: 状态点 + 设备编号 + 信号强度
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isConnected ? Colors.green : AppColors.socRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            device.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        RssiIndicator(rssi: device.rssi),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Row 2: 电压 + 电流 + 保护状态（横向滚动）
                    if (hasAdv)
                      Row(
                        children: [
                          _InfoChip(
                            icon: Icons.bolt,
                            text: '${adv.voltage.toStringAsFixed(3)}V',
                          ),
                          const SizedBox(width: 10),
                          _InfoChip(
                            icon: Icons.swap_horiz,
                            text: '${adv.current.toStringAsFixed(3)}A',
                          ),
                          if (activeFlags.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const _DividerDot(),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 20,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  shrinkWrap: true,
                                  itemCount: activeFlags.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 4),
                                  itemBuilder: (_, i) =>
                                      _FlagChip(flag: activeFlags[i]),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DividerDot extends StatelessWidget {
  const _DividerDot();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? Colors.white.withOpacity(0.2) : Colors.grey.shade400,
      ),
    );
  }
}

/// 保护状态标签
class _FlagChip extends StatelessWidget {
  final SafetyFlag flag;
  const _FlagChip({required this.flag});

  @override
  Widget build(BuildContext context) {
    final color =
        flag.isCritical ? SafetyFlags.criticalColor : SafetyFlags.warningColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        flag.label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 图标 + 文字 信息条
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.bmsTealLight),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
