# iOS 配置功能适配方案

> 记录时间：2026-08-27

## 背景

参数设置页的**一键配置**、**配置导出**，以及扩展页的**配置文件管理**，底层都依赖
`ConfigExportService._configDirectory()`。该方法当前硬编码 Android 路径
（`/storage/emulated/0/Download/bms_configs`），iOS 沙盒没有该路径、也没有 `HOME`/`USERPROFILE`
环境变量，导致 iOS 上三处功能全部失效。

目标：**双端可用，不影响 Android**。

## 阶段 1：存储路径修复（改动小，先做）

| 步骤 | 改动 | 状态 |
|---|---|---|
| 1.1 | `pubspec.yaml` 加 `path_provider: ^2.1.6` | ✅ 已加 |
| 1.2 | `config_export_service.dart` 的 `_configDirectory()` 加 iOS 分支：<br>`Platform.isIOS` → `getApplicationDocumentsDirectory()/bms_configs`；<br>Android 分支一行不动 | ⬜ 待做 |
| 1.3 | `ios/Runner/Info.plist` 加 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`，<br>导出文件在 iPhone「文件」App 可见 | ⬜ 待做 |

效果：三处配置功能 iOS 恢复；Android 零影响（分支隔离）。

## 阶段 2-B1：file_picker 导入（本次做）

| 步骤 | 改动 | 状态 |
|---|---|---|
| 2.1 | `pubspec.yaml` 加 `file_picker: ^11.0.3` | ✅ 已加 |
| 2.2 | 一键配置（`param_setting_tab`）加「导入文件」入口：<br>`file_picker` 选 .csv → `ConfigExportService.copyToConfigDir()` → 刷新列表 | ⬜ 待做 |

用户流程：微信/QQ 把 CSV 存到「文件」→ app 里一键配置 → 「导入文件」选择 → 出现在列表可一键写入。

## 阶段 2-B2：Share Extension（后续，暂缓）

- `receive_sharing_intent` + Xcode 添加 Share Extension target（改 `project.pbxproj`）+ App Group
- 微信/QQ **分享** → 直接进 app（和 Android 一致），体验最好但配置复杂
- 等阶段 1 + B1 测试通过后再考虑

## 当前状态 / 阻塞

- ✅ pubspec 依赖已添加（path_provider + file_picker）
- ❌ `flutter pub get` 因 **C 盘磁盘空间不足**失败（下载 `file_picker-11.0.3` 时中断，errno 112）
- ⏳ 待：清缓存腾出空间 → 重新 `flutter pub get` → 继续实施 1.2 / 1.3 / 2.2
