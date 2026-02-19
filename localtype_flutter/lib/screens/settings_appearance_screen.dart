import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_type_provider.dart';
import '../theme/app_theme.dart';
import 'theme_screen.dart';

class SettingsAppearanceScreen extends StatelessWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocalTypeProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('界面与外观'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                        _buildColorPreview(provider)
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.chat_bubble_outline_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('气泡样式'),
                  subtitle: Text(
                    provider.bubbleColorType == 'default' ? '极致简约' : '主题色调',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showBubbleColorDialog(context, provider),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
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
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.font_download_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('字体选择'),
                  subtitle: Text(
                    provider.useSystemFont ? '系统默认' : '内置字体',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showFontDialog(context, provider),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPreview(LocalTypeProvider provider) {
    final quadrants = AppTheme.getQuadrantColors(provider.seedColor,
        isDark: provider.isDarkMode);
    return SizedBox(
      width: 24,
      height: 24,
      child: ClipOval(
        child: Column(
          children: [
            Expanded(
                child: Row(children: [
              Expanded(child: Container(color: quadrants[0])),
              Expanded(child: Container(color: quadrants[1])),
            ])),
            Expanded(
                child: Row(children: [
              Expanded(child: Container(color: quadrants[2])),
              Expanded(child: Container(color: quadrants[3])),
            ])),
          ],
        ),
      ),
    );
  }

  String _getTransitionLabel(String type) {
    switch (type) {
      case 'sharedAxisX':
        return '共享轴 X';
      case 'sharedAxisY':
        return '共享轴 Y';
      case 'sharedAxisZ':
        return '共享轴 Z';
      case 'fadeThrough':
        return '淡入淡出';
      default:
        return '无动画';
    }
  }

  void _showBubbleColorDialog(
      BuildContext context, LocalTypeProvider provider) {
    showDialog(
      context: context,
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
                value: 'default',
              ),
              RadioListTile<String>(
                title: Text('主题色调'),
                value: 'primary',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransitionDialog(BuildContext context, LocalTypeProvider provider) {
    showDialog(
      context: context,
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

  Widget _buildTransitionOption(BuildContext context,
      LocalTypeProvider provider, String value, String title) {
    return RadioListTile<String>(
      title: Text(title),
      value: value,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _showFontDialog(BuildContext context, LocalTypeProvider provider) {
    showDialog(
      context: context,
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
                value: false,
              ),
              RadioListTile<bool>(
                title: Text('系统字体'),
                value: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
