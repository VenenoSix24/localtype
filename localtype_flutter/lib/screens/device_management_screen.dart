import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_type_provider.dart';

class DeviceManagementScreen extends StatelessWidget {
  const DeviceManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocalTypeProvider>(context);
    final theme = Theme.of(context);
    final pairedDevices = provider.pairedDevices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备管理'),
      ),
      body: pairedDevices.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices_rounded,
                      size: 64, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    '暂无已配对设备',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pairedDevices.length,
              itemBuilder: (context, index) {
                final device = pairedDevices[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.computer_rounded,
                          color: theme.colorScheme.primary),
                    ),
                    title: Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${device.ip} • ${device.os ?? "未知系统"}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'rename') {
                          _showRenameDialog(context, provider, device);
                        } else if (value == 'unpair') {
                          _showUnpairConfirmDialog(context, provider, device);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('重命名'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'unpair',
                          child: Row(
                            children: [
                              Icon(Icons.link_off_rounded,
                                  size: 20, color: theme.colorScheme.error),
                              const SizedBox(width: 8),
                              const Text('取消配对'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showRenameDialog(BuildContext context, LocalTypeProvider provider,
      DiscoveredDevice device) {
    final controller = TextEditingController(text: device.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名设备'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入新的设备名称',
            border: OutlineInputBorder(),
          ),
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
                provider.renamePairedDevice(device.ip, newName);
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showUnpairConfirmDialog(BuildContext context,
      LocalTypeProvider provider, DiscoveredDevice device) {
    showDialog(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('取消配对'),
          content: Text('确认要取消与设备 "${device.name}" 的配对吗？取消后将删除本地授权令牌。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('再想想'),
            ),
            FilledButton(
              onPressed: () {
                provider.unpairDevice(device.ip, serverId: device.serverId);
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(
                backgroundColor: dialogTheme.colorScheme.error,
                foregroundColor: dialogTheme.colorScheme.onError,
              ),
              child: const Text('确认取消'),
            ),
          ],
        );
      },
    );
  }
}
