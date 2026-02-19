import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_type_provider.dart';
import 'phrase_management_screen.dart';

class SettingsTypingScreen extends StatelessWidget {
  const SettingsTypingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocalTypeProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('输入与内容'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader(theme, '注入方式'),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<String>(
              groupValue: provider.injectionMethod,
              onChanged: (val) {
                if (val != null) provider.setInjectionMethod(val);
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    title: Text('Unicode（推荐）'),
                    subtitle: Text('直接模拟键盘输入，不影响剪贴板'),
                    value: 'unicode',
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<String>(
                    title: Text('剪贴板粘贴'),
                    subtitle: Text('通过 Ctrl+V / Cmd+V 粘贴'),
                    value: 'clipboard',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(theme, '内容管理'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_stories_rounded),
                  title: const Text('快捷短语管理'),
                  subtitle: Text('共有 ${provider.quickPhrases.length} 条短语'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PhraseManagementScreen()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('清除发送历史'),
                  subtitle: const Text('清空键盘页面的所有消息记录'),
                  onTap: () => _showClearHistoryDialog(context, provider),
                ),
              ],
            ),
          ),
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

  void _showClearHistoryDialog(
      BuildContext context, LocalTypeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空所有发送历史记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.clearHistory();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('历史记录已清空')),
              );
            },
            child: const Text('确定清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
