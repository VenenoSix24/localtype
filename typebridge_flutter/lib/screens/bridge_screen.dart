import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/type_bridge_provider.dart';

/// 连接页 —— Radar 风格设备发现与连接管理
/// 类似 LocalSend 的可视化设备池
class BridgeScreen extends StatefulWidget {
  const BridgeScreen({super.key});

  @override
  State<BridgeScreen> createState() => _BridgeScreenState();
}

class _BridgeScreenState extends State<BridgeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _radarController;
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<TypeBridgeProvider>(context, listen: false);
      provider.onPairingRequired = (msg) {
        _showPairingDialog(context);
      };
      _startScan();
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  void _startScan() {
    final provider = Provider.of<TypeBridgeProvider>(context, listen: false);
    if (!provider.isScanning) {
      setState(() => _showManualInput = false);
      provider.startDeviceDiscovery();
      _radarController.repeat();

      // 5 秒后如果没发现设备，显示手动输入提示
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && provider.discoveredDevices.isEmpty) {
          setState(() => _showManualInput = true);
        }
      });
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors_rounded,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('连接'),
          ],
        ),
        actions: [
          if (isConnected)
            TextButton.icon(
              onPressed: provider.disconnect,
              icon: Icon(Icons.link_off_rounded,
                  size: 16, color: theme.colorScheme.error),
              label: Text('断开',
                  style:
                      TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '重新扫描',
            onPressed: () {
              provider.stopDeviceDiscovery();
              _startScan();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (isConnected) _buildConnectedBanner(provider, theme),
          Expanded(
            child: isConnected
                ? _buildConnectedView(theme)
                : _buildRadarView(provider, theme),
          ),
          if (_showManualInput && !isConnected)
            _buildManualInput(provider, theme),
        ],
      ),
    );
  }

  Widget _buildConnectedBanner(TypeBridgeProvider provider, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.computer_rounded,
                color: theme.colorScheme.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已连接',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    )),
                const SizedBox(height: 4),
                Text(provider.connectedIp ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.7),
                    )),
              ],
            ),
          ),
          Icon(Icons.check_circle_rounded,
              color: Colors.green.shade400, size: 32),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1);
  }

  Widget _buildConnectedView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
                  size: 80, color: Colors.green.shade400)
              .animate()
              .scale(duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text('桥接就绪',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('切换到「键盘」标签页开始输入',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildRadarView(TypeBridgeProvider provider, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;

        return Stack(
          children: [
            // 雷达波纹
            if (provider.isScanning)
              ...List.generate(3, (i) {
                return Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _radarController,
                    builder: (context, child) {
                      final value = ((_radarController.value + i / 3) % 1.0);
                      final size = 160 + value * 200;
                      return Center(
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: (1 - value) * 0.25),
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),

            // 中心图标
            Positioned(
              left: centerX - 40,
              top: centerY - 40,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Icon(
                  provider.isScanning
                      ? Icons.sensors_rounded
                      : Icons.sensors_off_rounded,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),

            // 发现的设备卡片
            ...provider.discoveredDevices.asMap().entries.map((entry) {
              final index = entry.key;
              final device = entry.value;
              final totalDevices = provider.discoveredDevices.length;
              final angle =
                  (index * 2 * pi / (totalDevices > 1 ? totalDevices : 1)) -
                      pi / 2;
              const radius = 130.0;
              final dx = centerX + radius * cos(angle) - 50;
              final dy = centerY + radius * sin(angle) - 35;

              return Positioned(
                left: dx,
                top: dy,
                child: _buildDeviceCard(device, provider, theme, index),
              );
            }),

            // 底部状态
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: provider.isScanning
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary)),
                          const SizedBox(width: 8),
                          Text('正在搜索设备...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      )
                    : provider.discoveredDevices.isEmpty
                        ? TextButton.icon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('重新扫描'),
                          )
                        : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceCard(DiscoveredDevice device, TypeBridgeProvider provider,
      ThemeData theme, int index) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        provider.stopDeviceDiscovery();
        _radarController.stop();
        provider.connect(device.ip);
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.computer_rounded,
                size: 28, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(device.name,
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(device.ip,
                style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (index * 200).ms, duration: 400.ms).scale(
        begin: const Offset(0.8, 0.8),
        end: const Offset(1, 1),
        duration: 400.ms,
        curve: Curves.easeOutBack);
  }

  Widget _buildManualInput(TypeBridgeProvider provider, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('没有发现设备？试试手动输入',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: provider.ipController,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: '192.168.1.x',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: provider.status == ConnectionStatus.connecting
                    ? null
                    : () => provider.connect(provider.ipController.text),
                child: provider.status == ConnectionStatus.connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('连接'),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2);
  }
}
