import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/local_type_provider.dart';

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
  bool _showPhrases = false; // 是否显示快捷短语菜单

  @override
  void initState() {
    super.initState();
    _lastMessageCount = context.read<LocalTypeProvider>().messages.length;
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
      String action, LocalTypeProvider provider, ThemeData theme) {
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
        provider.deleteMessages(_selectedIds.toList());
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
    final provider = Provider.of<LocalTypeProvider>(context);
    final theme = Theme.of(context);
    final isConnected = provider.status == ConnectionStatus.connected &&
        provider.authStatus == AuthStatus.authenticated;

    // 修复：不在 build 方法中直接操作 AnimatedListState 这种 Mutation 式逻辑
    if (isConnected) {
      final currentCount = provider.messages.length;
      if (currentCount > _lastMessageCount) {
        final diff = currentCount - _lastMessageCount;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_listKey.currentState != null) {
            for (int i = 0; i < diff; i++) {
              _listKey.currentState!.insertItem(i);
            }
          }
        });
        _lastMessageCount = currentCount;
      } else if (currentCount < _lastMessageCount) {
        // 批量删除时，简单的做法是刷新整体状态或清空后重新分配
        // 本次优先保证不卡死，TODO: 完善 removeItem 动画细节
        _lastMessageCount = currentCount;
      }
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
        backgroundColor: theme.brightness == Brightness.light
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceContainerLow, // 暗黑模式下背景更深，拉开与气泡的距离
        appBar: _buildAppBar(context, provider, theme),
        body: !isConnected
            ? _buildDisconnectedView(theme)
            : Stack(
                children: [
                  // 聊天内容层：铺满全屏，让内容可以滚动到输入框下方
                  Positioned.fill(
                    child: AnimatedList(
                      key: _listKey,
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(
                          16, 20, 16, 80), // 缩短底部留白，使气泡更靠近输入框
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

                  // 输入区域层：浮动在最上方，透明背景
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildInputSection(context, provider, theme),
                  ),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, LocalTypeProvider provider, ThemeData theme) {
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
                surfaceTintColor: Colors.transparent, // 防止滚动变色
                backgroundColor: theme.colorScheme.surface,
              )
            : AppBar(
                key: const ValueKey('normal_appbar'),
                centerTitle: true,
                backgroundColor: theme.colorScheme.surface,
                surfaceTintColor: Colors.transparent, // 防止滚动变色
                elevation: 0,
                scrolledUnderElevation: 1,
                title: Column(
                  children: [
                    Text(
                      provider.remoteServerName ?? 'LocalType',
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
      LocalTypeProvider provider,
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
      BuildContext context, LocalTypeProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16), // 上下左右边距统一为 16px
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // 带有动画的垂直弹出菜单 (现在作为 Column 的一部分，解决点击和遮挡问题)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              reverseDuration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: _showPhrases
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildPhraseMenu(context, provider, theme),
                    )
                  : const SizedBox.shrink(),
            ),

            // 通体圆角输入框 (TG 风格)
            Container(
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.light
                    ? theme.colorScheme.surface
                    : theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: theme.brightness == Brightness.light
                        ? Colors.black.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 左侧菜单按钮
                  IconButton(
                    onPressed: () {
                      setState(() => _showPhrases = !_showPhrases);
                      HapticFeedback.mediumImpact();
                    },
                    icon: Icon(
                      _showPhrases ? Icons.close_rounded : Icons.menu_rounded,
                      size: 20,
                    ),
                    color: _showPhrases
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onPrimary,
                    style: IconButton.styleFrom(
                      backgroundColor: _showPhrases
                          ? theme.colorScheme.primary.withValues(alpha: 0.1)
                          : Color.lerp(theme.colorScheme.primary, Colors.white,
                              0.15), // 与气泡同步提亮
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 输入框
                  Expanded(
                    child: TextField(
                      key: const PageStorageKey('chat_input_field'),
                      controller: provider.textController,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      contextMenuBuilder: (context, editableTextState) {
                        final List<ContextMenuButtonItem> buttonItems =
                            editableTextState.contextMenuButtonItems;
                        buttonItems.insert(
                          0,
                          ContextMenuButtonItem(
                            label: '全屏视角',
                            onPressed: () {
                              ContextMenuController.removeAny();
                              _showFullscreenInput(context, provider);
                            },
                          ),
                        );
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: buttonItems,
                        );
                      },
                      decoration: const InputDecoration(
                        hintText: '开始输入吧...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                        fillColor: Colors.transparent, // 背景与胶囊背景合一
                        filled: true,
                      ),
                      style: const TextStyle(fontSize: 16),
                      scrollPadding: const EdgeInsets.only(bottom: 20),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 集成发送按钮
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      provider.sendText();
                    },
                    icon: const Icon(Icons.send_rounded, size: 20),
                    color: theme.colorScheme.onPrimary,
                    style: IconButton.styleFrom(
                      backgroundColor: Color.lerp(theme.colorScheme.primary,
                          Colors.white, 0.15), // 与气泡同步提亮
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
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

  Widget _buildPhraseMenu(
      BuildContext context, LocalTypeProvider provider, ThemeData theme) {
    if (provider.quickPhrases.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const Text('暂无快捷短语'),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddPhraseDialog(context, provider),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('去添加'),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.light
                ? Colors.black.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: theme.brightness == Brightness.light
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: provider.quickPhrases.length + 1,
          itemBuilder: (context, index) {
            if (index == provider.quickPhrases.length) {
              return ListTile(
                dense: true,
                minVerticalPadding: 0,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.add_circle_outline_rounded, size: 18),
                title: const Text('管理/添加新短语', style: TextStyle(fontSize: 13)),
                onTap: () {
                  _showAddPhraseDialog(context, provider);
                },
              );
            }
            final phrase = provider.quickPhrases[index];
            return ListTile(
              dense: true,
              minVerticalPadding: 0,
              visualDensity: VisualDensity.compact,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              title: Text(phrase.label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              trailing: Text(
                phrase.content.length > 20
                    ? '${phrase.content.substring(0, 20)}...'
                    : phrase.content,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () {
                final text = phrase.content;
                final controller = provider.textController;
                final currentText = controller.text;
                final selection = controller.selection;

                if (selection.isValid) {
                  final newText = currentText.replaceRange(
                    selection.start,
                    selection.end,
                    text,
                  );
                  controller.text = newText;
                  // 移动光标到插入文本之后
                  controller.selection = TextSelection.collapsed(
                    offset: selection.start + text.length,
                  );
                } else {
                  controller.text += text;
                }

                HapticFeedback.lightImpact();
                setState(() => _showPhrases = false);
                _focusNode.requestFocus(); // 保持焦点
              },
              onLongPress: () {
                _showPhraseOptions(context, provider, phrase);
              },
            );
          },
        ),
      ),
    );
  }

  void _showFullscreenInput(BuildContext context, LocalTypeProvider provider) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '全屏输入',
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

  void _showAddPhraseDialog(BuildContext context, LocalTypeProvider provider) {
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

  void _showPhraseOptions(
      BuildContext context, LocalTypeProvider provider, QuickPhrase phrase) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('编辑短语'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditPhraseDialog(context, provider, phrase);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('删除短语', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _showDeletePhraseDialog(context, provider, phrase);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showEditPhraseDialog(
      BuildContext context, LocalTypeProvider provider, QuickPhrase phrase) {
    final labelCtrl = TextEditingController(text: phrase.label);
    final contentCtrl = TextEditingController(text: phrase.content);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Text('编辑快捷短语'),
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
                  provider.updatePhrase(phrase.id, label, content);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('保存修改'),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePhraseDialog(
      BuildContext context, LocalTypeProvider provider, QuickPhrase phrase) {
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
        builder: (context, scrollController) => Consumer<LocalTypeProvider>(
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
  final LocalTypeProvider provider;
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

    final isThemeColor = widget.provider.bubbleColorType == 'primary';

    // 提亮并保持鲜艳度的逻辑
    final vibrantThemeColor =
        Color.lerp(theme.colorScheme.primary, Colors.white, 0.15)!;

    final bubbleColor = widget.isSelected
        ? theme.colorScheme.primaryContainer
        : isThemeColor
            ? vibrantThemeColor
            : theme.brightness == Brightness.light
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerHigh;

    final contentColor = widget.isSelected
        ? theme.colorScheme.onPrimaryContainer
        : isThemeColor
            ? theme.colorScheme.onPrimary // 提亮 15% 依然属于深色，白色文字更鲜艳
            : theme.colorScheme.onSurface;

    final metadataColor = contentColor.withValues(alpha: 0.7);

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
              left: widget.isSelectionMode ? 42 : 16, right: 16), // 稍微增加间距给勾选框
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 左侧勾选框 (TG 风格)
              if (widget.isSelectionMode)
                Positioned(
                  left: -34,
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  margin: EdgeInsets.only(
                      left: widget.isSelectionMode
                          ? 18
                          : 44), // 重要：减少 margin 以补偿 padding 的增加，保持总宽度稳定
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _isPressed = true),
                    onTapCancel: () => setState(() => _isPressed = false),
                    onTapUp: (_) => setState(() => _isPressed = false),
                    child: AnimatedScale(
                      scale: _isPressed ? 0.98 : 1.0, // 减小缩放幅度，使其更稳重
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(4),
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.brightness == Brightness.light
                                  ? Colors.black.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              message.text,
                              style: TextStyle(
                                color: contentColor,
                                fontSize: 16,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: metadataColor,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _buildStatusIconInner(
                                    message.status, theme, metadataColor),
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

  Widget _buildStatusIconInner(
      MessageStatus status, ThemeData theme, Color color) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.2,
            color: color,
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.done_rounded, size: 14, color: color);
      case MessageStatus.acked:
        return Icon(Icons.done_all_rounded, size: 14, color: color);
      case MessageStatus.error:
        return const Icon(Icons.error_outline_rounded,
            size: 14, color: Colors.red);
    }
  }
}
