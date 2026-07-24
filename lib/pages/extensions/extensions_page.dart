import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../i18n/app_strings.dart';
import '../../i18n/locale_provider.dart';

/// 扩展页 — 语言切换等设置
class ExtensionsPage extends ConsumerWidget {
  const ExtensionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.shell.moreTitle),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(s.shell.language),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.locale == AppLocale.zh ? '中文' : 'English',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
              onTap: () => _showPicker(context, ref, s),
            ),
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, AppStrings s) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.common.selectLanguage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            RadioListTile<AppLocale>(
              title: const Text('中文'),
              value: AppLocale.zh,
              groupValue: s.locale,
              onChanged: (v) { ref.read(localeProvider.notifier).setLocale(v!); Navigator.pop(context); },
            ),
            RadioListTile<AppLocale>(
              title: const Text('English'),
              value: AppLocale.en,
              groupValue: s.locale,
              onChanged: (v) { ref.read(localeProvider.notifier).setLocale(v!); Navigator.pop(context); },
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.common.cancel)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
    );
  }
}
