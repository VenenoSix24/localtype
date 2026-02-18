import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/local_type_provider.dart';
import '../theme/app_theme.dart';
import '../screens/theme_screen.dart';
import '../screens/device_management_screen.dart';
import '../screens/phrase_management_screen.dart';

/// 设置页面
/// 包含外观、注入方式、连接信息和关于等设置项
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocalTypeProvider>(context);
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => _showEditDeviceNameDialog(context, provider),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.phonelink_setup_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('管理已配对设备'),
                  subtitle: Text(
                    '查看及管理已授权的 ${provider.pairedDevices.length} 台设备',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const DeviceManagementScreen()),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 快捷短语管理
          _buildSectionHeader(theme, '内容管理'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.auto_stories_rounded,
                  color: theme.colorScheme.primary),
              title: const Text('快捷短语管理'),
              subtitle: Text(
                '共有 ${provider.quickPhrases.length} 条短语',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const PhraseManagementScreen()),
                );
              },
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

          // 外观
          _buildSectionHeader(theme, '外观'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
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
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.palette_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('主题配色'),
                  subtitle: Text(
                    provider.useDynamicColor ? '动态取色已开启' : '点击选择主题颜色',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!provider.useDynamicColor)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: ClipOval(
                            child: Builder(builder: (context) {
                              final quadrants = AppTheme.getQuadrantColors(
                                  provider.seedColor,
                                  isDark: provider.isDarkMode);
                              return Column(
                                children: [
                                  Expanded(
                                      child: Row(children: [
                                    Expanded(
                                        child: Container(color: quadrants[0])),
                                    Expanded(
                                        child: Container(color: quadrants[1])),
                                  ])),
                                  Expanded(
                                      child: Row(children: [
                                    Expanded(
                                        child: Container(color: quadrants[2])),
                                    Expanded(
                                        child: Container(color: quadrants[3])),
                                  ])),
                                ],
                              );
                            }),
                          ),
                        )
                      else
                        Icon(Icons.auto_awesome_rounded,
                            size: 20,
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.5)),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ThemeScreen()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.font_download_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('选择字体'),
                  subtitle: Text(
                    '点击选择当前软件字体',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        provider.useSystemFont ? '系统默认' : '内置字体',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () => _showFontDialog(context, provider),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 聊天气泡
          _buildSectionHeader(theme, '聊天气泡'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.chat_bubble_outline_rounded,
                  color: theme.colorScheme.primary),
              title: const Text('气泡背景'),
              subtitle: Text(
                provider.bubbleColorType == 'default'
                    ? '极致简约 (白色/悬浮)'
                    : '主题色调 (活力)',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showBubbleColorDialog(context, provider),
            ),
          ),

          const SizedBox(height: 24),

          // 页面动画
          _buildSectionHeader(theme, '页面动画'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.animation_rounded,
                  color: theme.colorScheme.primary),
              title: const Text('过渡动画'),
              subtitle: Text(
                _getTransitionLabel(provider.pageTransitionType),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showTransitionDialog(context, provider),
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
                  leading: const Icon(Icons.info_outline_rounded),
                  iconColor: theme.colorScheme.onSurfaceVariant,
                  title: const Text('LocalType'),
                  subtitle: Text(
                    'v1.2.2',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  iconColor: theme.colorScheme.onSurfaceVariant,
                  title: const Text('源代码'),
                  subtitle: Text(
                    'GitHub 仓库',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(Icons.open_in_new_rounded,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  onTap: () {
                    launchUrl(
                        Uri.parse('https://github.com/VenenoSix24/localtype'));
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'Made with ♥ by LocalType',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _getTransitionLabel(String type) {
    switch (type) {
      case 'sharedAxisX':
        return '共享轴 X (平滑横移)';
      case 'sharedAxisY':
        return '共享轴 Y (垂直位移)';
      case 'sharedAxisZ':
        return '共享轴 Z (缩放渐变)';
      case 'fadeThrough':
        return '淡入淡出 (Fade Through)';
      default:
        return '无动画 (默认)';
    }
  }

  void _showTransitionDialog(BuildContext context, LocalTypeProvider provider) {
    showModal<void>(
      context: context,
      configuration: const FadeScaleTransitionConfiguration(),
      builder: (ctx) => AlertDialog(
        title: const Text('选择过渡动画'),
        content: RadioGroup<String>(
          groupValue: provider.pageTransitionType,
          onChanged: (val) {
            if (val != null) {
              provider.setPageTransitionType(val);
              Navigator.pop(ctx);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTransitionOption(ctx, provider, 'sharedAxisX', '共享轴 X'),
              _buildTransitionOption(ctx, provider, 'sharedAxisY', '共享轴 Y'),
              _buildTransitionOption(ctx, provider, 'sharedAxisZ', '共享轴 Z'),
              _buildTransitionOption(ctx, provider, 'fadeThrough', '淡入淡出'),
              _buildTransitionOption(ctx, provider, 'default', '无动画'),
            ],
          ),
        ),
      ),
    );
  }

  void _showFontDialog(BuildContext context, LocalTypeProvider provider) {
    showModal<void>(
      context: context,
      configuration: const FadeScaleTransitionConfiguration(),
      builder: (ctx) => AlertDialog(
        title: const Text('选择软件字体'),
        content: RadioGroup<bool>(
          groupValue: provider.useSystemFont,
          onChanged: (val) {
            if (val != null) {
              provider.setUseSystemFont(val);
              Navigator.pop(ctx);
            }
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                title: Text('内置字体'),
                subtitle: Text('使用软件内置的 Poppins 字体'),
                value: false,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                title: Text('系统默认字体'),
                subtitle: Text('使用手机系统中设置的默认字体'),
                value: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBubbleColorDialog(
      BuildContext context, LocalTypeProvider provider) {
    showModal<void>(
      context: context,
      configuration: const FadeScaleTransitionConfiguration(),
      builder: (ctx) => AlertDialog(
        title: const Text('选择气泡背景'),
        content: RadioGroup<String>(
          groupValue: provider.bubbleColorType,
          onChanged: (val) {
            if (val != null) {
              provider.setBubbleColorType(val);
              Navigator.pop(ctx);
            }
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text('极致简约'),
                subtitle: Text('白色/灰色背景，悬浮阴影感'),
                value: 'default',
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                title: Text('主题色调'),
                subtitle: Text('跟随当前主题色种子颜色'),
                value: 'primary',
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransitionOption(BuildContext context,
      LocalTypeProvider provider, String value, String title) {
    return RadioListTile<String>(
      title: Text(title),
      value: value,
      contentPadding: EdgeInsets.zero,
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

  /// 修改设备名称对话框
  void _showEditDeviceNameDialog(
      BuildContext context, LocalTypeProvider provider) {
    final controller = TextEditingController(text: provider.deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('修改设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '请输入设备名称',
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          maxLength: 20,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                provider.setDeviceName(newName);
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
