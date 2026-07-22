import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/abnormal_record.dart';
import '../models/device_model.dart';
import '../services/bluetooth_service.dart';
import '../services/realtime_poller.dart';

// ============================================================
// 蓝牙服务实例
// ============================================================

final bluetoothServiceProvider = Provider<BluetoothService>((ref) {
  return BluetoothService.instance;
});

// ============================================================
// 连接状态
// ============================================================

final isConnectedProvider = StateProvider<bool>((ref) => false);

final connectionResultProvider =
    StateProvider<ConnectionResult?>((ref) => null);

/// 当前连接的设备信息（用于列表高亮和快速返回）
final connectedDeviceProvider = StateProvider<DeviceModel?>((ref) => null);

/// 参数设置缓存 {groupCode: values[]}，跨页面实例存活
final paramCacheProvider =
    StateProvider<Map<String, List<dynamic>>>((ref) => {});

/// 异常记录缓存，跨页面实例存活
final recordCacheProvider = StateProvider<List<AbnormalRecord>>((ref) => []);

/// 异常记录缓存所属设备的 protocolId
final recordCacheOwnerProvider = StateProvider<String?>((ref) => null);

// ============================================================
// 实时轮询器
// ============================================================

final realtimePollerProvider = StateProvider<RealtimePoller?>((ref) => null);

// ============================================================
// 实时数据缓存（BatteryInfoTab 消费）
// ============================================================

/// 实时数据缓存 {groupCode: {nameEnglish: value}}
/// 每次 RealtimePoller 轮询成功后更新
final realtimeDataProvider =
    StateProvider<Map<String, Map<String, dynamic>>>((ref) => {});

// ============================================================
// 连接操作
// ============================================================

/// 缓存同步 Timer（需在断开时取消）
Timer? _syncTimer;

/// 执行完整连接流程
final connectDeviceProvider =
    FutureProvider.family<ConnectionResult, String>((ref, deviceId) async {
  try {
    final service = ref.read(bluetoothServiceProvider);
    final result = await service.connectAndInit(deviceId);

    // 停掉旧轮询器（必须在 await 之后，避免同步初始化期间修改其他 provider）
    final oldPoller = ref.read(realtimePollerProvider);
    oldPoller?.stop();

    service.onDisconnected = () {
      ref.read(isConnectedProvider.notifier).state = false;
      ref.read(connectionResultProvider.notifier).state = null;
      ref.read(connectedDeviceProvider.notifier).state = null;
    };

    ref.read(isConnectedProvider.notifier).state = true;
    ref.read(connectionResultProvider.notifier).state = result;

    // 启动实时轮询
    final rtGroups = result.bundle.realtimeGroups;
    final poller = RealtimePoller(service, rtGroups);
    poller.onCycleDone = () {
      if (service.isConnected) {
        ref.read(realtimeDataProvider.notifier).state =
            Map<String, Map<String, dynamic>>.from(poller.cache);
      }
    };
    ref.read(realtimePollerProvider.notifier).state = poller;
    poller.start();

    // 立即同步 + 每1s兜底同步
    void sync() {
      if (!service.isConnected) return;
      ref.read(realtimeDataProvider.notifier).state =
          Map<String, Map<String, dynamic>>.from(poller.cache);
    }
    _syncTimer?.cancel();
    sync();
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) => sync());

    return result;
  } catch (_) {
    // 失败时清理残留状态
    ref.read(isConnectedProvider.notifier).state = false;
    ref.read(connectionResultProvider.notifier).state = null;
    ref.read(realtimePollerProvider)?.stop();
    ref.read(realtimePollerProvider.notifier).state = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    rethrow;
  }
});

/// 断开连接
final disconnectDeviceProvider = FutureProvider<void>((ref) async {
  final service = ref.read(bluetoothServiceProvider);
  _syncTimer?.cancel();
  _syncTimer = null;
  ref.read(realtimePollerProvider)?.stop();
  ref.read(realtimePollerProvider.notifier).state = null;
  ref.read(isConnectedProvider.notifier).state = false;
  ref.read(connectionResultProvider.notifier).state = null;
  ref.read(connectedDeviceProvider.notifier).state = null;
  ref.read(realtimeDataProvider.notifier).state = {};
  ref.read(paramCacheProvider.notifier).state = {};
  ref.read(recordCacheProvider.notifier).state = [];
  ref.read(recordCacheOwnerProvider.notifier).state = null;
  await service.disconnect();
});
