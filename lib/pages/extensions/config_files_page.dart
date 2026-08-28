import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../i18n/app_strings.dart';
import '../../i18n/locale_provider.dart';
import '../../services/config_export_service.dart';

/// 配置文件管理页面
class ConfigFilesPage extends ConsumerStatefulWidget {
  const ConfigFilesPage({super.key});

  @override
  ConsumerState<ConfigFilesPage> createState() => _ConfigFilesPageState();
}

class _ConfigFilesPageState extends ConsumerState<ConfigFilesPage> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final files = await ConfigExportService.listSavedConfigs();
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.shell.configFiles),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.share_outlined,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(s.shell.noConfigFiles,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 15)),
                        const SizedBox(height: 8),
                        Text(
                          s.locale == AppLocale.zh
                              ? '在微信/QQ 或文件管理器中打开 .csv 文件\n选择"分享"或"用其他应用打开" → 选择本应用即可导入'
                              : 'Open .csv file in WeChat/QQ or file manager\nTap "Share" or "Open with" → select this app to import',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _files.length,
                    itemBuilder: (_, i) {
                      final file = _files[i];
                      final name = file.uri.pathSegments.last;
                      final size = file.lengthSync();
                      final date = file.lastModifiedSync();
                      final dateStr =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
                          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading:
                              const Icon(Icons.description, color: Colors.blue),
                          title: Text(name,
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '$dateStr  ${(size / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'share') {
                                await _shareFile(file, name, s);
                              } else if (action == 'delete') {
                                _deleteFile(file, s);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    const Icon(Icons.share, size: 18),
                                    const SizedBox(width: 8),
                                    Text(s.shell.shareFile),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete_outline,
                                        size: 18, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text(s.shell.deleteConfig,
                                        style: const TextStyle(
                                            color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  /// 转发配置文件
  /// iOS 26 起要求 sharePositionOrigin（缺失时分享面板不弹出），
  /// 锚点取当前页面渲染区域；iPad 上同样生效。
  Future<void> _shareFile(File file, String name, AppStrings s) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: name,
        sharePositionOrigin: box == null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${s.shell.shareFile}失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _deleteFile(File file, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.delete_outline, color: Colors.red, size: 24),
          const SizedBox(width: 8),
          Text(s.shell.deleteConfig),
        ]),
        content: Text(
          '${s.shell.deleteConfigConfirm}\n\n${file.uri.pathSegments.last}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.common.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.shell.deleteConfig,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await file.delete();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(s.shell.deleted),
              duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${s.shell.deleted}: $e'),
              duration: const Duration(seconds: 2)),
        );
      }
    }
  }
}
