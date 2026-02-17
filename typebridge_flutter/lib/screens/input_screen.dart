import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/type_bridge_provider.dart';

/// 输入页 —— 文本输入 + 历史记录 + 快捷短语
/// V1.1: 增加历史记录条和自定义短语快捷发送
class InputScreen extends StatelessWidget {
  const InputScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TypeBridgeProvider>(context);
    final theme = Theme.of(context);
    final isConnected = provider.status == ConnectionStatus.connected &&
        provider.authStatus == AuthStatus.authenticated;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_alt_rounded,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('键盘'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal_rounded, size: 20),
            tooltip: '日志',
            onPressed: () => _showLogs(context),
          ),
        ],
      ),
      body: !isConnected
          ? _buildDisconnectedView(theme)
          : Column(
              children: [
                // 快捷操作条（历史+短语）
                _buildQuickBar(context, provider, theme),

                // 模式切换栏
                _buildModeBar(provider, theme),

                // 文本输入区
                Expanded(child: _buildInputArea(provider, theme)),

                // 底部留白
                SizedBox(height: provider.isRealtime ? 16 : 80),
              ],
            ),
      floatingActionButton: isConnected && !provider.isRealtime
          ? FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.lightImpact();
                provider.sendText();
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('发送'),
            )
          : null,
    );
  }

  Widget _buildDisconnectedView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link_off_rounded,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('未连接',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('请先在「连接」页面桥接电脑',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  /// 快捷操作条：历史记录 + 自定义短语
  Widget _buildQuickBar(
      BuildContext context, TypeBridgeProvider provider, ThemeData theme) {
    final hasContent =
        provider.sendHistory.isNotEmpty || provider.quickPhrases.isNotEmpty;

    if (!hasContent) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: OutlinedButton.icon(
          onPressed: () => _showAddPhraseDialog(context, provider),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('添加快捷短语'),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // 添加按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 14),
              label: const Text('添加', style: TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _showAddPhraseDialog(context, provider),
            ),
          ),

          // 自定义短语
          ...provider.quickPhrases.map((phrase) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: GestureDetector(
                  onLongPress: () =>
                      _showDeletePhraseDialog(context, provider, phrase),
                  child: ActionChip(
                    avatar: Icon(Icons.flash_on_rounded,
                        size: 14, color: theme.colorScheme.primary),
                    label: Text(phrase.label,
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      provider.sendDirectText(phrase.content);
                    },
                  ),
                ),
              )),

          // 分隔线
          if (provider.sendHistory.isNotEmpty &&
              provider.quickPhrases.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: VerticalDivider(
                  width: 1, color: theme.colorScheme.outlineVariant),
            ),

          // 历史记录
          ...provider.sendHistory.map((text) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: ActionChip(
                  avatar: Icon(Icons.history_rounded,
                      size: 14, color: theme.colorScheme.outline),
                  label: Text(
                    text.length > 15 ? '${text.substring(0, 15)}...' : text,
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    provider.sendDirectText(text);
                  },
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildModeBar(TypeBridgeProvider provider, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: provider.isRealtime
                  ? theme.colorScheme.tertiaryContainer
                  : theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  provider.isRealtime
                      ? Icons.flash_on_rounded
                      : Icons.chat_rounded,
                  size: 14,
                  color: provider.isRealtime
                      ? theme.colorScheme.onTertiaryContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  provider.isRealtime ? '实时模式' : '聊天模式',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: provider.isRealtime
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: provider.isRealtime,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                provider.toggleRealtime(val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(TypeBridgeProvider provider, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TextField(
        controller: provider.textController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.6),
        decoration: InputDecoration(
          hintText: provider.isRealtime ? '输入内容将自动发送到电脑...' : '在这里输入要发送的文字...',
          hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
        onChanged: (val) {
          if (provider.isRealtime) {
            provider.sendRealtimeText(val);
          }
        },
      ),
    );
  }

  // ==================== 对话框 ====================

  void _showAddPhraseDialog(BuildContext context, TypeBridgeProvider provider) {
    final labelCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('添加快捷短语'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(
                  labelText: '标签名',
                  hintText: '例如：邮箱',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '内容',
                  hintText: '例如：example@email.com',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelCtrl.text.trim();
                final content = contentCtrl.text.trim();
                if (label.isNotEmpty && content.isNotEmpty) {
                  provider.addPhrase(label, content);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePhraseDialog(
      BuildContext context, TypeBridgeProvider provider, QuickPhrase phrase) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('删除短语'),
        content: Text('确定要删除「${phrase.label}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              provider.removePhrase(phrase.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showLogs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Consumer<TypeBridgeProvider>(
          builder: (context, provider, child) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('运行日志',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${provider.logs.length} 条',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: provider.logs.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Text(
                        provider.logs[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
