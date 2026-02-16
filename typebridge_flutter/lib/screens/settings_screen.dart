import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/type_bridge_provider.dart';

/// 设置页面
/// 包含外观、注入方式、连接信息和关于等设置项
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TypeBridgeProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 外观
          _buildSectionHeader(theme, '外观'),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: Icon(
                  provider.isDarkMode
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  color: theme.colorScheme.primary),
              title: const Text('深色模式'),
              subtitle: Text(
                provider.isDarkMode ? '夜间护眼' : '明亮清晰',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              value: provider.isDarkMode,
              onChanged: (val) => provider.toggleTheme(val),
            ),
          ),

          const SizedBox(height: 24),

          // 注入方式
          _buildSectionHeader(theme, '注入方式'),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<String>(
              groupValue: provider.injectionMethod,
              onChanged: (val) {
                if (val != null) provider.setInjectionMethod(val);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('Unicode（推荐）'),
                    subtitle: Text(
                      '直接模拟键盘输入，不影响剪贴板',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13),
                    ),
                    value: 'unicode',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<String>(
                    title: Row(
                      children: [
                        const Text('剪贴板粘贴'),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '实验性',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '通过 Ctrl+V / Cmd+V 粘贴\nmacOS 上可能不稳定',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13),
                    ),
                    value: 'clipboard',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 连接管理
          _buildSectionHeader(theme, '连接管理'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.devices_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('设备名称'),
                  subtitle: Text(
                    provider.deviceName ?? '未知设备',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: theme.colorScheme.error),
                  title: Text(
                    '清除配对信息',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: Text(
                    '清除后需重新与电脑配对',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13),
                  ),
                  onTap: () => _showClearPairingDialog(context, provider),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 关于
          _buildSectionHeader(theme, '关于'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.keyboard_alt_rounded,
                        color: theme.colorScheme.primary, size: 20),
                  ),
                  title: const Text('TypeBridge'),
                  subtitle: Text(
                    'v1.1.0',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.code_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                  title: const Text('源代码'),
                  subtitle: Text(
                    'GitHub 仓库',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(Icons.open_in_new_rounded,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  onTap: () {
                    // TODO: 跳转 GitHub 链接
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'Made with ♥ by TypeBridge',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 清除配对信息确认对话框
  void _showClearPairingDialog(
      BuildContext context, TypeBridgeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.warning_amber_rounded,
            size: 36, color: Colors.orange),
        title: const Text('清除配对信息'),
        content: const Text('清除后将断开当前连接，下次连接需要重新输入验证码进行配对。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.disconnect();
              provider.clearPairingData();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
  }
}
