import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'i18n/locale_provider.dart';
import 'pages/bluetooth/bluetooth_page.dart';
import 'pages/scan/scan_page.dart';
import 'pages/extensions/extensions_page.dart';

/// 应用入口
class BmsApp extends ConsumerWidget {
  const BmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: '小龙电动',
      debugShowCheckedModeBanner: false,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: themeMode,
      home: const MainShell(),
    );
  }
}

/// 主框架 — 磨砂玻璃底部导航
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;
  final _scanActiveNotifier = ValueNotifier<bool>(false);

  late final _pages = [
    const BluetoothPage(),
    ScanPage(isActiveNotifier: _scanActiveNotifier),
    const ExtensionsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _FrostedNavBar(
          labels: [s.shell.tabBt, s.shell.tabScan, s.shell.tabMore],
        currentIndex: _currentIndex,
        onTap: (i) => setState(() {
          _currentIndex = i;
          _scanActiveNotifier.value = i == 1;
        }),
      ),
    );
  }

  @override
  void dispose() {
    _scanActiveNotifier.dispose();
    super.dispose();
  }
}

/// 磨砂玻璃底部导航栏
class _FrostedNavBar extends StatelessWidget {
  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _FrostedNavBar({required this.currentIndex, required this.onTap, required this.labels});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.72),
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.15),
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.bluetooth,
                  label: labels[0],
                  isSelected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
                _NavItem(
                  icon: Icons.qr_code_scanner,
                  label: labels[1],
                  isSelected: currentIndex == 1,
                  onTap: () => onTap(1),
                ),
                _NavItem(
                  icon: Icons.widgets,
                  label: labels[2],
                  isSelected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isSelected ? scheme.primary : scheme.onSurfaceVariant;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: isSelected ? 1.0 : 0.88,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? _filledVariant(icon) : icon,
                  size: 24,
                  color: color,
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _filledVariant(IconData icon) {
    switch (icon) {
      case Icons.bluetooth:
        return Icons.bluetooth_connected;
      case Icons.qr_code_scanner:
        return Icons.qr_code;
      default:
        return icon;
    }
  }
}

/// 占位页面
class _PlaceholderPage extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlaceholderPage({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
