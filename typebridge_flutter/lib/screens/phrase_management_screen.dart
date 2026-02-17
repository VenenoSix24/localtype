import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/type_bridge_provider.dart';

class PhraseManagementScreen extends StatefulWidget {
  const PhraseManagementScreen({super.key});

  @override
  State<PhraseManagementScreen> createState() => _PhraseManagementScreenState();
}

class _PhraseManagementScreenState extends State<PhraseManagementScreen> {
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelected(TypeBridgeProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 条快捷短语吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.removePhrases(_selectedIds.toList());
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TypeBridgeProvider>(context);
    final theme = Theme.of(context);
    final phrases = provider.quickPhrases;

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('已选择 ${_selectedIds.length}')
            : const Text('快捷短语管理'),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close), onPressed: _clearSelection)
            : const BackButton(),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteSelected(provider),
              color: theme.colorScheme.error,
            )
          else
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _showAddEditDialog(context, provider),
            ),
        ],
      ),
      body: phrases.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.short_text_rounded,
                      size: 64, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text('暂无快捷短语',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showAddEditDialog(context, provider),
                    icon: const Icon(Icons.add),
                    label: const Text('添加第一个短语'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: phrases.length,
              itemBuilder: (context, index) {
                final phrase = phrases[index];
                final isSelected = _selectedIds.contains(phrase.id);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isSelected
                        ? BorderSide(color: theme.colorScheme.primary, width: 2)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(phrase.label,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        phrase.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    trailing: _isSelectionMode
                        ? Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelection(phrase.id),
                          )
                        : IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _showAddEditDialog(
                                context, provider,
                                phrase: phrase),
                          ),
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleSelection(phrase.id);
                      }
                    },
                    onLongPress: () {
                      if (!_isSelectionMode) {
                        _toggleSelection(phrase.id);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }

  void _showAddEditDialog(BuildContext context, TypeBridgeProvider provider,
      {QuickPhrase? phrase}) {
    final isEdit = phrase != null;
    final labelController = TextEditingController(text: phrase?.label);
    final contentController = TextEditingController(text: phrase?.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? '编辑短语' : '新建短语'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: '标签 (如：问候)'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              decoration: const InputDecoration(labelText: '内容'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final label = labelController.text.trim();
              final content = contentController.text.trim();
              if (label.isNotEmpty && content.isNotEmpty) {
                if (isEdit) {
                  provider.updatePhrase(phrase.id, label, content);
                } else {
                  provider.addPhrase(label, content);
                }
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
