import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_device_screen.dart';
import 'settings_appearance_screen.dart';
import 'settings_typing_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_rounded,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('设置'),
          ],
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildMenuCard(
            context,
            icon: Icons.cell_tower_rounded,
            title: '设备与连接',
            subtitle: '修改本机名称、管理已配对电脑',
            color: Colors.blue,
            destination: const SettingsDeviceScreen(),
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            icon: Icons.keyboard_command_key_rounded,
            title: '输入与内容',
            subtitle: '注入方式、快捷短语、历史记录',
            color: Colors.orange,
            destination: const SettingsTypingScreen(),
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            icon: Icons.palette_rounded,
            title: '界面与外观',
            subtitle: '深色模式、主题配色、气泡样式',
            color: Colors.purple,
            destination: const SettingsAppearanceScreen(),
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            icon: Icons.info_outline_rounded,
            title: '软件版本',
            subtitle: '点击检查更新 | 当前版本 v1.2.5',
            color: Colors.teal,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已是最新版本')),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            icon: Icons.code_rounded,
            title: '项目源码',
            subtitle: '在 GitHub 上查看本项目源码',
            color: Colors.indigo,
            onTap: () {
              launchUrl(Uri.parse('https://github.com/VenenoSix24/localtype'));
            },
          ),
          const SizedBox(height: 48),
          Center(
            child: Text(
              'Made with ♥ by LocalType',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    Widget? destination,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ??
              () {
                if (destination != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => destination),
                  );
                }
              },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  onTap != null
                      ? Icons.open_in_new_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
