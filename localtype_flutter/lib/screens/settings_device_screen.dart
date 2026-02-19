import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_type_provider.dart';
import 'device_management_screen.dart';

class SettingsDeviceScreen extends StatelessWidget {
  const SettingsDeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocalTypeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备与连接'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_rounded),
                  title: const Text('本机端名称'),
                  subtitle: Text(provider.deviceName ?? '未设置'),
                  trailing: const Icon(Icons.edit_rounded, size: 20),
                  onTap: () => _showEditDeviceNameDialog(context, provider),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.devices_other_rounded),
                  title: const Text('管理已配对设备'),
                  subtitle: Text('已配对 ${provider.pairedDevices.length} 台电脑'),
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
        ],
      ),
    );
  }

  void _showEditDeviceNameDialog(
      BuildContext context, LocalTypeProvider provider) {
    final controller = TextEditingController(text: provider.deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入新的名称',
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
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                provider.setDeviceName(name);
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
