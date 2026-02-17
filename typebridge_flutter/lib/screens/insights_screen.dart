import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_type_provider.dart';

/// 统计看板 —— 字数统计与仪式感数据
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocalTypeProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('成就'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 核心数据卡片
            _buildMainStatsCard(provider, theme),
            const SizedBox(height: 16),

            // 今日数据
            _buildTodayCard(provider, theme),
            const SizedBox(height: 24),

            // 里程碑
            _buildSectionHeader(theme, '里程碑'),
            const SizedBox(height: 12),
            Builder(builder: (ctx) => _buildMilestones(ctx, provider, theme)),
            const SizedBox(height: 24),

            // 隐私说明
            _buildPrivacyNote(theme),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatsCard(LocalTypeProvider provider, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text('累计输入',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              )),
          const SizedBox(height: 8),
          Text(
            _formatNumber(provider.totalChars),
            style: theme.textTheme.displayMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text('字符',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              )),
        ],
      ),
    );
  }

  Widget _buildTodayCard(LocalTypeProvider provider, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.today_rounded,
                  color: theme.colorScheme.onSecondaryContainer, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日输入',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(
                    _formatNumber(provider.todayChars),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Text('字符',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestones(
      BuildContext context, LocalTypeProvider provider, ThemeData theme) {
    final milestones = [
      _Milestone('初出茅庐', 100, Icons.emoji_events_outlined),
      _Milestone('小试牛刀', 1000, Icons.workspace_premium_outlined),
      _Milestone('渐入佳境', 5000, Icons.military_tech_outlined),
      _Milestone('炉火纯青', 10000, Icons.stars_rounded),
      _Milestone('出神入化', 50000, Icons.diamond_outlined),
      _Milestone('键盘之神', 100000, Icons.auto_awesome),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: milestones.map((m) {
        final achieved = provider.totalChars >= m.threshold;

        return Container(
          width: (MediaQuery.of(context).size.width - 44) / 2,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: achieved
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: achieved
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Column(
            children: [
              Icon(
                m.icon,
                size: 28,
                color: achieved
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                m.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: achieved
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.outline,
                ),
              ),
              Text(
                '${_formatNumber(m.threshold)} 字',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: achieved
                      ? theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.7)
                      : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrivacyNote(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '所有统计数据仅保存在本地，不会上传任何内容',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          )),
    );
  }

  String _formatNumber(int number) {
    if (number >= 10000) {
      return '${(number / 10000).toStringAsFixed(1)}万';
    }
    return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
}

class _Milestone {
  final String title;
  final int threshold;
  final IconData icon;

  _Milestone(this.title, this.threshold, this.icon);
}
