import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/type_bridge_provider.dart';

/// 连接页 —— Connection Hub (v2)
/// Top: Status Panel
/// Bottom: Nearby & Saved Devices (Card Style)
class BridgeScreen extends StatefulWidget {
  const BridgeScreen({super.key});

  @override
  State<BridgeScreen> createState() => _BridgeScreenState();
}

class _BridgeScreenState extends State<BridgeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<TypeBridgeProvider>(context, listen: false);
      provider.onPairingRequired = (msg) {
        _showPairingDialog(context);
      };
      // Start discovery automatically
      _startScan();
    });
  }

  void _startScan() {
    final provider = Provider.of<TypeBridgeProvider>(context, listen: false);
    if (!provider.isScanning) {
      provider.startDeviceDiscovery();
    }
  }

  void _showPairingDialog(BuildContext context) {
    final TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: Icon(Icons.lock_outline,
              size: 40, color: theme.colorScheme.primary),
          title: const Text('设备配对'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '请输入电脑端弹窗中显示的 6 位验证码',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '000000',
                  counterText: '',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Provider.of<TypeBridgeProvider>(context, listen: false)
                    .disconnect();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final code = codeController.text.trim();
                if (code.isNotEmpty) {
                  Navigator.pop(ctx);
                  Provider.of<TypeBridgeProvider>(context, listen: false)
                      .submitPairingCode(code);
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TypeBridgeProvider>(context);
    final theme = Theme.of(context);
    final isConnected = provider.status == ConnectionStatus.connected &&
        provider.authStatus == AuthStatus.authenticated;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备连接'),
        actions: [
          IconButton(
            icon: provider.isScanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.colorScheme.primary))
                : const Icon(Icons.refresh_rounded),
            onPressed: _startScan,
            tooltip: '重新扫描',
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_rounded),
            tooltip: '手动输入 IP',
            onPressed: () => _showManualInputDialog(context, provider),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Top: Status Panel
          SliverToBoxAdapter(
            child: _buildStatusPanel(provider, theme, isConnected),
          ),

          // List Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  Text(
                    '附近设备',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (provider.isScanning)
                    Text(
                      '正在搜索...',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    )
                        .animate(onPlay: (c) => c.repeat())
                        .fade(duration: 1.seconds),
                ],
              ),
            ),
          ),

          // Device List
          _buildDeviceList(provider, theme),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(
      TypeBridgeProvider provider, ThemeData theme, bool isConnected) {
    final statusColor = isConnected ? Colors.green : Colors.orange;
    final statusText = isConnected
        ? '已连接'
        : (provider.status == ConnectionStatus.connecting ? '连接中...' : '尚未连接');

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ]),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        if (isConnected)
                          BoxShadow(
                              color: statusColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2)
                      ]),
                ),
                const SizedBox(width: 12),
                Text(
                  statusText,
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: statusColor),
                ),
                const Spacer(),
                if (isConnected)
                  TextButton(
                    onPressed: provider.disconnect,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                      minimumSize: Size.zero,
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('断开连接', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem(theme, Icons.wifi_rounded, '对方 IP',
                    provider.connectedIp ?? '未检测'),
                _buildStatusItem(theme, Icons.computer_rounded, '对方名称',
                    provider.remoteServerName ?? '无'),
              ],
            ),
            if (isConnected) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '输入管道已就绪',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildStatusItem(
      ThemeData theme, IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildDeviceList(TypeBridgeProvider provider, ThemeData theme) {
    final discovered = provider.discoveredDevices;
    final paired = provider.pairedDevices;

    // Merge results: Discovered ones take priority
    final allDevices = <String, DiscoveredDevice>{};
    for (var d in paired) {
      allDevices[d.ip] = d;
    }
    for (var d in discovered) {
      allDevices[d.ip] = d;
    }

    final sortedItems = allDevices.values.toList()
      ..sort((a, b) {
        // Connected one first
        if (provider.connectedIp == a.ip) return -1;
        if (provider.connectedIp == b.ip) return 1;
        // Online ones second
        bool aOnline = discovered.any((d) => d.ip == a.ip);
        bool bOnline = discovered.any((d) => d.ip == b.ip);
        if (aOnline && !bOnline) return -1;
        if (!aOnline && bOnline) return 1;
        return 0;
      });

    if (sortedItems.isEmpty && !provider.isScanning) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.portable_wifi_off_rounded,
                  size: 64, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 16),
              Text('未发现可用设备',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('请确保电脑端已启动且处于同一局域网',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final device = sortedItems[index];
            final isOnline = discovered.any((d) => d.ip == device.ip);
            final isSaved = paired.any((d) => d.ip == device.ip);

            return Card(
              elevation: 0,
              color: isOnline
                  ? theme.colorScheme.surfaceContainerHigh
                  : theme.colorScheme.surfaceContainerLow
                      .withValues(alpha: 0.5),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: isOnline
                    ? BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        width: 1)
                    : BorderSide.none,
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.desktop_windows_rounded,
                    color: isOnline
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isOnline)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('在线',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _buildTag(theme, '#${device.ip.split('.').last}',
                          theme.colorScheme.secondary),
                      if (device.os != null && device.os!.isNotEmpty)
                        _buildTag(
                            theme,
                            device.os!.toUpperCase(),
                            device.os!.toLowerCase().contains('mac')
                                ? Colors.grey
                                : Colors.blue),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider.connectedIp == device.ip &&
                        provider.status == ConnectionStatus.connected)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('已连接',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    IconButton(
                      icon: Icon(
                        isSaved
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color:
                            isSaved ? Colors.orange : theme.colorScheme.outline,
                      ),
                      onPressed: () {
                        provider.toggleFavorite(
                            device.ip, device.name, device.os ?? '');
                      },
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  provider.connect(device.ip);
                },
              ),
            )
                .animate()
                .fadeIn(delay: (index * 50).ms)
                .slideX(begin: 0.05, end: 0);
          },
          childCount: sortedItems.length,
        ),
      ),
    );
  }

  void _showManualInputDialog(
      BuildContext context, TypeBridgeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动连接'),
        content: TextField(
          controller: provider.ipController,
          decoration: const InputDecoration(
            labelText: '输入 IP 地址',
            hintText: '192.168.1.x',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.connect(provider.ipController.text);
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
