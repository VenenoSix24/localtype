import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/local_type_provider.dart';

/// 连接页面 —— 连接中心
/// 顶部：状态面板
/// 底部：附近和已保存的设备（卡片样式）
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<LocalTypeProvider>(context, listen: false);
      provider.onPairingRequired = (msg) {
        _showPairingDialog(context);
      };
      // 自动开始扫描
      _startScan();
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _startScan() {
    final provider = Provider.of<LocalTypeProvider>(context, listen: false);
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
                Provider.of<LocalTypeProvider>(context, listen: false)
                    .disconnect();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final code = codeController.text.trim();
                if (code.isNotEmpty) {
                  Navigator.pop(ctx);
                  Provider.of<LocalTypeProvider>(context, listen: false)
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
    final provider = Provider.of<LocalTypeProvider>(context);
    final theme = Theme.of(context);
    final isConnected = provider.status == ConnectionStatus.connected &&
        provider.authStatus == AuthStatus.authenticated;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors_rounded, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('连接'),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // 顶部：状态面板
          SliverToBoxAdapter(
            child: _buildStatusPanel(provider, theme, isConnected),
          ),

          // 列表标题
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
                  const SizedBox(width: 8),
                  if (provider.isScanning)
                    Text(
                      '正在搜索...',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  const Spacer(),
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: AnimatedBuilder(
                      animation: _rotationController,
                      builder: (context, child) {
                        // 当开始扫描时，如果动画没在运行，则启动
                        if (provider.isScanning &&
                            !_rotationController.isAnimating) {
                          _rotationController.repeat();
                        } else if (!provider.isScanning &&
                            _rotationController.isAnimating) {
                          _rotationController.stop();
                        }
                        return RotationTransition(
                          turns: _rotationController,
                          child: const Icon(Icons.sync_rounded),
                        );
                      },
                    ),
                    onPressed: _startScan,
                    tooltip: '重新扫描',
                  ),
                ],
              ),
            ),
          ),

          // 设备列表
          ..._buildDeviceSlivers(provider, theme),

          // 手动输入入口页脚
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 40),
              child: Center(
                child: TextButton(
                  onPressed: () => _showManualInputDialog(context, provider),
                  child: Text(
                    '没有找到设备？试试手动输入',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(
      LocalTypeProvider provider, ThemeData theme, bool isConnected) {
    final statusColor = isConnected ? Colors.green : Colors.orange;
    String statusText = isConnected ? '已连接' : '尚未连接';
    if (provider.status == ConnectionStatus.connecting) {
      statusText = provider.reconnectAttempts > 0
          ? '自动重连中 (${provider.reconnectAttempts}/5)'
          : '正在连接...';
    } else if (provider.status == ConnectionStatus.error) {
      statusText = '连接失败，准备重连...';
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
        ),
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
                        if (isConnected ||
                            provider.status == ConnectionStatus.connecting)
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
                if (provider.remoteServerName != null)
                  TextButton(
                    onPressed: provider.disconnect,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                      minimumSize: Size.zero,
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(
                        provider.status == ConnectionStatus.connecting
                            ? '取消'
                            : '断开连接',
                        style: const TextStyle(fontSize: 12)),
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
                      '输入通道已就绪',
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
    );
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

  List<Widget> _buildDeviceSlivers(
      LocalTypeProvider provider, ThemeData theme) {
    final discovered = provider.discoveredDevices;
    final paired = provider.pairedDevices;

    // 分类设备
    final pairedIps = paired.map((d) => d.ip).toSet();
    final pairedItems = [...paired];
    // 如果某个已配对设备当前在线，更新其信息（如名称可能变了）
    for (int i = 0; i < pairedItems.length; i++) {
      final onlineMatch =
          discovered.where((d) => d.ip == pairedItems[i].ip).toList();
      if (onlineMatch.isNotEmpty) {
        pairedItems[i] = onlineMatch.first;
      }
    }

    final unpairedNearbyItems =
        discovered.where((d) => !pairedIps.contains(d.ip)).toList();

    // 排序逻辑保持主次：已连接 > 在线 > 离线
    void sortDevices(List<DiscoveredDevice> list) {
      list.sort((a, b) {
        if (provider.connectedIp == a.ip) return -1;
        if (provider.connectedIp == b.ip) return 1;
        bool aOnline = discovered.any((d) => d.ip == a.ip);
        bool bOnline = discovered.any((d) => d.ip == b.ip);
        if (aOnline && !bOnline) return -1;
        if (!aOnline && bOnline) return 1;
        return 0;
      });
    }

    sortDevices(pairedItems);
    sortDevices(unpairedNearbyItems);

    if (pairedItems.isEmpty &&
        unpairedNearbyItems.isEmpty &&
        !provider.isScanning) {
      return [
        SliverFillRemaining(
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
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _showManualInputDialog(context, provider),
                  icon: const Icon(Icons.keyboard_rounded, size: 18),
                  label: const Text('手动输入 IP 地址'),
                ),
              ],
            ),
          ),
        )
      ];
    }

    final List<Widget> slivers = [];

    // 1. 已配对设备
    if (pairedItems.isNotEmpty) {
      slivers.add(_buildListHeader(theme, '已配对设备', Icons.bookmark_rounded));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final device = pairedItems[index];
                final isOnline = discovered.any((d) => d.ip == device.ip);
                return _buildDeviceItem(
                    context, provider, theme, device, isOnline, true);
              },
              childCount: pairedItems.length,
            ),
          ),
        ),
      );
    }

    // 2. 未配对/附近设备
    if (unpairedNearbyItems.isNotEmpty) {
      slivers.add(_buildListHeader(theme, '扫描到的新设备', Icons.radar_rounded));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final device = unpairedNearbyItems[index];
                const isOnline = true; // 出现在 discovered 列表里的一定是在线的
                return _buildDeviceItem(
                    context, provider, theme, device, isOnline, false);
              },
              childCount: unpairedNearbyItems.length,
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _buildListHeader(ThemeData theme, String title, IconData icon) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: theme.colorScheme.primary.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceItem(
    BuildContext context,
    LocalTypeProvider provider,
    ThemeData theme,
    DiscoveredDevice device,
    bool isOnline,
    bool isSaved,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              if (isOnline) {
                provider.connect(device.ip);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('设备 "${device.name}" 目前不在线'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 图标容器
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isOnline
                          ? theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.7)
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.desktop_windows_rounded,
                      color: isOnline
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 信息区块
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isOnline) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _buildTag(
                                theme,
                                device.ip,
                                theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6)),
                            if (device.os != null && device.os!.isNotEmpty)
                              _buildTag(
                                  theme,
                                  device.os!.toUpperCase(),
                                  theme.colorScheme.primary
                                      .withValues(alpha: 0.8)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 尾部操作区
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          isSaved
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: isSaved
                              ? Colors.orange
                              : theme.colorScheme.outline,
                          size: 24,
                        ),
                        onPressed: () {
                          provider.toggleFavorite(device.ip, device.name,
                              device.os, device.serverId);
                        },
                      ),
                      if (provider.connectedIp == device.ip &&
                          provider.status == ConnectionStatus.connected)
                        const Icon(Icons.link_rounded,
                            color: Colors.green, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showManualInputDialog(
      BuildContext context, LocalTypeProvider provider) {
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
