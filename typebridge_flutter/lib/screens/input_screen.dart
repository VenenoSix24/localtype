import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/type_bridge_provider.dart';

/// 键盘页面 (聊天流模式)
/// V1.2.1: 细节优化与交互增强
class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final Set<String> _selectedIds = {}; // 当前选中的消息 ID 集合
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = context.read<TypeBridgeProvider>().messages.length;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _handleBatchAction(
      String action, TypeBridgeProvider provider, ThemeData theme) {
    final selectedMessages =
        provider.messages.where((m) => _selectedIds.contains(m.id)).toList();

    if (selectedMessages.isEmpty) return;

    switch (action) {
      case 'copy':
        final text = selectedMessages.reversed.map((m) => m.text).join('\n');
        Clipboard.setData(ClipboardData(text: text));
        _clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('已复制 ${selectedMessages.length} 条消息'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            width: 220,
            margin: null, // width 设置后 margin 需处理
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            // 提示：如果要避开键盘/输入框，可以使用 bottom margin 配合 floating
          ),
        );
        break;
      case 'edit':
        if (selectedMessages.length == 1) {
          provider.textController.text = selectedMessages.first.text;
          _focusNode.requestFocus();
          _clearSelection();
        }
        break;
      case 'delete':
        // TODO: 实现批量删除
        _clearSelection();
        break;
      case 'resend':
        for (var m in selectedMessages) {
          provider.sendDirectText(m.text);
        }
        _clearSelection();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TypeBridgeProvider>(context);
    final theme = Theme.of(context);
    final isConnected = provider.status == ConnectionStatus.connected &&
        provider.authStatus == AuthStatus.authenticated;

    if (isConnected) {
      final currentCount = provider.messages.length;
      if (currentCount > _lastMessageCount) {
        final diff = currentCount - _lastMessageCount;
        for (int i = 0; i < diff; i++) {
          _listKey.currentState?.insertItem(i);
        }
      }
      _lastMessageCount = currentCount;
    }

    // 使用 PopScope 拦截手机返回键/手势
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          _clearSelection();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: _buildAppBar(context, provider, theme),
        body: !isConnected
            ? _buildDisconnectedView(theme)
            : Column(
                children: [
                  Expanded(
                    child: AnimatedList(
                      key: _listKey,
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 20),
                      initialItemCount: provider.messages.length,
                      itemBuilder: (context, index, animation) {
                        if (index >= provider.messages.length) {
                          return const SizedBox.shrink();
                        }
                        final message = provider.messages[index];
                        return _buildAnimatedBubble(
                            context, message, theme, provider, animation);
                      },
                    ),
                  ),
                  _buildInputSection(context, provider, theme),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, TypeBridgeProvider provider, ThemeData theme) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _isSelectionMode
            ? AppBar(
                key: const ValueKey('selection_appbar'),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _clearSelection,
                ),
                title: Text('${_selectedIds.length}'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () =>
                        _handleBatchAction('copy', provider, theme),
                    tooltip: '复制',
                  ),
                  if (_selectedIds.length == 1)
                    IconButton(
                      icon: const Icon(Icons.edit_note_rounded, size: 24),
                      onPressed: () =>
                          _handleBatchAction('edit', provider, theme),
                      tooltip: '编辑',
                    ),
                  IconButton(
                    icon: const Icon(Icons.send_and_archive_rounded, size: 20),
                    onPressed: () =>
                        _handleBatchAction('resend', provider, theme),
                    tooltip: '再次发送',
                  ),
                  const SizedBox(width: 8),
                ],
              )
            : AppBar(
                key: const ValueKey('normal_appbar'),
                centerTitle: true,
                title: Column(
                  children: [
                    Text(
                      provider.remoteServerName ?? 'TypeBridge',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: provider.status == ConnectionStatus.connected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          provider.status == ConnectionStatus.connected
                              ? '已连接'
                              : '未连接',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: provider.status == ConnectionStatus.connected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.terminal_rounded, size: 20),
                    onPressed: () => _showLogs(context),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDisconnectedView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hub_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            '未连接',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text('请先在「连接」页面选择设备',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildAnimatedBubble(
      BuildContext context,
      MessageModel message,
      ThemeData theme,
      TypeBridgeProvider provider,
      Animation<double> animation) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: ScaleTransition(
          scale: curvedAnimation,
          alignment:
              message.isSystem ? Alignment.center : Alignment.bottomRight,
          child: _ChatBubble(
            message: message,
            provider: provider,
            isSelected: _selectedIds.contains(message.id),
            isSelectionMode: _isSelectionMode,
            onTap: () {
              if (_isSelectionMode) {
                _toggleSelection(message.id);
              }
            },
            onLongPress: () {
              if (!_isSelectionMode) {
                _toggleSelection(message.id);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection(
      BuildContext context, TypeBridgeProvider provider, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildQuickPhrasesBar(context, provider, theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: provider.textController,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                hintText: '输入内容...',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 10),
                              ),
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.fullscreen_rounded, size: 20),
                            onPressed: () =>
                                _showFullscreenInput(context, provider),
                            color: theme.colorScheme.primary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      provider.sendText();
                    },
                    icon: Icon(Icons.send_rounded,
                        color: theme.colorScheme.primary),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullscreenInput(BuildContext context, TypeBridgeProvider provider) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fullscreen Input',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('全屏输入'),
            actions: [
              TextButton(
                onPressed: () {
                  provider.sendText();
                  Navigator.pop(ctx);
                },
                child: const Text('发送'),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: provider.textController,
              maxLines: null,
              expands: true,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '开始长文本创作...',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 17, height: 1.6),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickPhrasesBar(
      BuildContext context, TypeBridgeProvider provider, ThemeData theme) {
    // 如果在选择模式下，隐藏快捷短语栏
    if (_isSelectionMode) return const SizedBox.shrink();

    return SizedBox(
      height: 54,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: provider.quickPhrases.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                onPressed: () => _showAddPhraseDialog(context, provider),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                ),
              ),
            );
          }

          final phrase = provider.quickPhrases[index - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onLongPress: () =>
                  _showDeletePhraseDialog(context, provider, phrase),
              child: ActionChip(
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                label: Text(
                  phrase.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () =>
                    _showConfirmSendPhraseDialog(context, provider, phrase),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showConfirmSendPhraseDialog(
      BuildContext context, TypeBridgeProvider provider, QuickPhrase phrase) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认发送「${phrase.label}」?'),
        content:
            Text(phrase.content, maxLines: 5, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              provider.sendDirectText(phrase.content);
              Navigator.pop(ctx);
            },
            child: const Text('确认发送'),
          ),
        ],
      ),
    );
  }

  void _showAddPhraseDialog(BuildContext context, TypeBridgeProvider provider) {
    final labelCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Text('添加快捷短语'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(
                  labelText: '标签名',
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '内容',
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('删除短语'),
        content: Text('确定要删除「${phrase.label}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              provider.removePhrase(phrase.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
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

/// 独立的聊天气泡组件，处理选择模式和交互
class _ChatBubble extends StatefulWidget {
  final MessageModel message;
  final TypeBridgeProvider provider;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChatBubble({
    required this.message,
    required this.provider,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;

    if (message.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        splashColor: Colors.transparent,
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          padding: EdgeInsets.only(
              left: widget.isSelectionMode ? 40 : 16, right: 16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 左侧勾选框 (TG 风格)
              if (widget.isSelectionMode)
                Positioned(
                  left: -32,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      widget.isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: widget.isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.5),
                      size: 22,
                    ),
                  ),
                ),

              // 气泡内容
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(left: 44),
                  child: GestureDetector(
                    onPanDown: (_) => setState(() => _isPressed = true),
                    onPanCancel: () => setState(() => _isPressed = false),
                    onPanEnd: (_) => setState(() => _isPressed = false),
                    child: AnimatedScale(
                      scale: _isPressed ? 0.96 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: widget.isSelected
                              ? Color.lerp(theme.colorScheme.primaryContainer,
                                  theme.colorScheme.primary, 0.1)
                              : theme.colorScheme.primaryContainer,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(2),
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          border: widget.isSelected
                              ? Border.all(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  width: 1)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: _isPressed ? 0.02 : 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              message.text,
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: theme.colorScheme.onPrimaryContainer
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _buildStatusIconInner(message.status, theme),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIconInner(MessageStatus status, ThemeData theme) {
    final opacityColor =
        theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7);
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: opacityColor,
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.done_rounded, size: 14, color: opacityColor);
      case MessageStatus.acked:
        return Icon(Icons.done_all_rounded, size: 14, color: opacityColor);
      case MessageStatus.error:
        return const Icon(Icons.error_outline_rounded,
            size: 14, color: Colors.red);
    }
  }
}
