import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mock 数据开关 — false=真实BLE扫描, true=Mock数据演示
final useMockDataProvider = StateProvider<bool>((ref) => false);
