import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/type_bridge_provider.dart';
import '../theme/app_theme.dart';

/// 主题选择二级页面
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TypeBridgeProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择应用主题'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 动态取色设置
          _buildDynamicColorCard(provider, theme),
          const SizedBox(height: 16),

          // 调色板网格
          if (!provider.useDynamicColor) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 16),
              child: Text(
                '调色板风格',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildThemeGrid(provider, theme),
          ] else
            _buildDynamicColorInfo(theme),
        ],
      ),
    );
  }

  Widget _buildDynamicColorCard(TypeBridgeProvider provider, ThemeData theme) {
    return Card(
      child: SwitchListTile(
        secondary:
            Icon(Icons.palette_rounded, color: theme.colorScheme.primary),
        title: const Text('动态取色'),
        subtitle: Text(
          '基于壁纸颜色（Android 12+）',
          style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        value: provider.useDynamicColor,
        onChanged: (val) => provider.setUseDynamicColor(val),
      ),
    );
  }

  Widget _buildDynamicColorInfo(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              '当前已开开启动态取色',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '界面色彩将自动适配你的壁纸风格',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeGrid(TypeBridgeProvider provider, ThemeData theme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 20,
        crossAxisSpacing: 16,
        childAspectRatio: 0.7, // 进一步增加垂直空间，防止文字溢出
      ),
      itemCount: AppTheme.themeColors.length,
      itemBuilder: (ctx, i) {
        final item = AppTheme.themeColors[i];
        final color = item['color'] as Color;
        final name = item['name'] as String;
        final isSelected = provider.seedColor == color;

        final quadrants =
            AppTheme.getQuadrantColors(color, isDark: provider.isDarkMode);

        return GestureDetector(
          onTap: () => provider.setThemeColor(color),
          child: Column(
            children: [
              // 强制正圆形的四分位预览
              AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: color.withValues(alpha: 0.3),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
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
                    ),
                    if (isSelected)
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black26, // 加一层半透明背景让 Checkmark 更清晰
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 24),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.bold : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
