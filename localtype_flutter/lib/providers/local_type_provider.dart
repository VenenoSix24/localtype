import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/update_service.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

enum AuthStatus { authenticated, unauthenticated, pairingRequired }

/// 已发现/已配对的设备信息
class DiscoveredDevice {
  final String ip;
  final String name;
  final String? os;
  final String? serverId;
  final DateTime discoveredAt;

  DiscoveredDevice({
    required this.ip,
    required this.name,
    this.os,
    this.serverId,
    required this.discoveredAt,
  });
}

/// 自定义短语
class QuickPhrase {
  final String id;
  final String label;
  final String content;

  QuickPhrase({
    required this.id,
    required this.label,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'content': content,
      };

  factory QuickPhrase.fromJson(Map<String, dynamic> json) => QuickPhrase(
        id: json['id'] as String,
        label: json['label'] as String,
        content: json['content'] as String,
      );
}

/// 消息发送状态
enum MessageStatus { sending, sent, acked, error }

/// 聊天消息模型
class MessageModel {
  final String id;
  final String text;
  final DateTime timestamp;
  final bool isSystem;
  MessageStatus status;

  MessageModel({
    required this.id,
    required this.text,
    required this.timestamp,
    this.isSystem = false,
    this.status = MessageStatus.sending,
  });
}

/// LocalType 核心状态管理
class LocalTypeProvider extends ChangeNotifier with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  AuthStatus _authStatus = AuthStatus.unauthenticated;
  final List<String> _logs = [];
  final TextEditingController ipController = TextEditingController();
  final TextEditingController textController = TextEditingController();
  HttpClient? _client;

  bool _isDarkMode = false;
  bool _useDynamicColor = false;
  Color _seedColor = const Color(0xFF4CAF50);
  String? _deviceId;
  String? _deviceName; // 本地设备名称
  String? _remoteServerName; // 已连接的服务端名称
  String? _remoteServerId; // 已连接的服务端 ID
  String? _remoteServerOs; // 已连接的服务端 OS
  Map<String, String> _tokens = {}; // serverId (或 ip) -> token

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastConnectedIp;
  String _injectionMethod = 'unicode';

  // --- V1.1 设备发现 ---
  final List<DiscoveredDevice> _discoveredDevices = [];
  bool _isScanning = false;
  Timer? _scanTimer;

  // --- V1.1 已配对设备 ---
  List<DiscoveredDevice> _pairedDevices = [];
  bool _isInitialized = false;

  // --- V1.1 历史记录 ---
  List<String> _sendHistory = [];
  static const int _maxHistory = 10;

  // --- V1.1 快捷短语 ---
  List<QuickPhrase> _quickPhrases = [];

  // --- V1.1 字数统计 ---
  int _totalChars = 0;
  int _todayChars = 0;
  String _todayDateKey = '';
  String _pageTransitionType = 'sharedAxisX';
  String _bubbleColorType = 'default';
  bool _useSystemFont = false;

  // --- V1.2 聊天流 ---
  final List<MessageModel> _messages = [];

  // --- 更新检查 ---
  String? _currentVersion;
  UpdateInfo? _updateInfo;
  bool _isCheckingUpdate = false;

  /// 配对对话框回调
  Function(String)? onPairingRequired;

  // Getter 方法
  ConnectionStatus get status => _status;
  AuthStatus get authStatus => _authStatus;
  List<String> get logs => _logs;
  bool get isDarkMode => _isDarkMode;
  String get injectionMethod => _injectionMethod;
  String? get connectedIp => _lastConnectedIp;
  String? get deviceName => _deviceName;
  String? get remoteServerName => _remoteServerName;
  List<DiscoveredDevice> get discoveredDevices => _discoveredDevices;
  List<DiscoveredDevice> get pairedDevices => _pairedDevices;
  bool get isScanning => _isScanning;
  List<String> get sendHistory => _sendHistory;
  List<QuickPhrase> get quickPhrases => _quickPhrases;
  int get totalChars => _totalChars;
  int get todayChars => _todayChars;
  int get reconnectAttempts => _reconnectAttempts;
  Color get seedColor => _seedColor;
  bool get useSystemFont => _useSystemFont;
  bool get useDynamicColor => _useDynamicColor;
  String get pageTransitionType => _pageTransitionType;
  String get bubbleColorType => _bubbleColorType;
  List<MessageModel> get messages => List.unmodifiable(_messages);
  String get currentVersion => _currentVersion ?? '...';
  UpdateInfo? get updateInfo => _updateInfo;
  bool get isCheckingUpdate => _isCheckingUpdate;

  /// 批量删除消息
  void deleteMessages(List<String> ids) {
    _messages.removeWhere((m) => ids.contains(m.id));
    notifyListeners();
  }

  LocalTypeProvider() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHeartbeat();
    _stopReconnect();
    _scanTimer?.cancel();
    _channel?.sink.close();
    ipController.dispose();
    textController.dispose();
    _client?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isInitialized) return; // Wait for initial load
      addLog('应用回到前台，检查连接状态...');
      if (_lastConnectedIp != null &&
          _status == ConnectionStatus.disconnected) {
        addLog('检测到断开，正在重连...');
        _reconnectAttempts = 0;
        connect(_lastConnectedIp!);
      }
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    _deviceName = prefs.getString('device_name');
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;

    // 加载多设备 Token
    final tokensJson = prefs.getString('auth_tokens');
    if (tokensJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(tokensJson);
        _tokens = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (e) {
        addLog('加载 Tokens 失败: $e');
      }
    }
    _useDynamicColor = prefs.getBool('use_dynamic_color') ?? false;
    _injectionMethod = prefs.getString('injection_method') ?? 'unicode';
    final savedColor = prefs.getInt('seed_color');
    if (savedColor != null) {
      _seedColor = Color(savedColor);
    }

    if (_deviceId == null) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
        _deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
        _deviceName = iosInfo.name;
      } else {
        _deviceId = 'generic_device_${Random().nextInt(10000)}';
        _deviceName = 'Generic Device';
      }
      await prefs.setString('device_id', _deviceId!);
      await prefs.setString('device_name', _deviceName!);
    }

    // Load History
    final historyJson = prefs.getStringList('send_history');
    if (historyJson != null) _sendHistory = historyJson;

    // Load Phrases
    final phrasesJson = prefs.getString('quick_phrases');
    if (phrasesJson != null) {
      final List<dynamic> decoded = jsonDecode(phrasesJson);
      _quickPhrases = decoded.map((e) => QuickPhrase.fromJson(e)).toList();
    }

    // Load Stats
    _totalChars = prefs.getInt('total_chars') ?? 0;
    _todayDateKey = _getTodayKey();
    _todayChars = prefs.getInt('today_chars_$_todayDateKey') ?? 0;

    // Load Page Transition Preference
    _pageTransitionType =
        prefs.getString('page_transition_type') ?? 'sharedAxisX';
    _bubbleColorType = prefs.getString('bubble_color_type') ?? 'default';
    _useSystemFont = prefs.getBool('use_system_font') ?? false;

    // Load Paired Devices
    await _loadPairedDevices();

    // Load current version
    final packageInfo = await PackageInfo.fromPlatform();
    _currentVersion = packageInfo.version;

    _isInitialized = true;
    notifyListeners();

    // Silent auto-check for updates
    checkForUpdate(silent: true);
  }

  // ==================== 已配对设备逻辑 ====================

  Future<void> _loadPairedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('paired_devices');
    if (jsonList != null) {
      try {
        _pairedDevices = jsonList.map((str) {
          final data = jsonDecode(str);
          return DiscoveredDevice(
            ip: data['ip'],
            name: data['name'] ?? 'Unknown',
            os: data['os'],
            serverId: data['serverId'],
            discoveredAt:
                DateTime.tryParse(data['discoveredAt'] ?? '') ?? DateTime.now(),
          );
        }).toList();
      } catch (e) {
        addLog('加载已配对设备出错: $e');
      }
    }
  }

  Future<void> toggleFavorite(
      String ip, String name, String? os, String? serverId) async {
    // 优先使用 serverId 识别设备，避免 IP 变化导致重复条目
    final isSaved = serverId != null
        ? _pairedDevices.any((d) => d.serverId == serverId)
        : _pairedDevices.any((d) => d.ip == ip);
    if (isSaved) {
      await removePairedDevice(ip, serverId: serverId);
      addLog('已从收藏库移除: $name');
    } else {
      await _savePairedDevice(ip, name, os, serverId);
      addLog('已加入收藏库: $name');
    }
  }

  Future<void> _savePairedDevice(
      String ip, String name, String? os, String? serverId) async {
    // 优先使用 serverId 匹配已有设备，IP 变化时自动更新而非新增
    final index = serverId != null
        ? _pairedDevices.indexWhere((d) => d.serverId == serverId)
        : _pairedDevices.indexWhere((d) => d.ip == ip);
    if (index != -1) {
      final existing = _pairedDevices[index];
      _pairedDevices[index] = DiscoveredDevice(
          ip: ip,
          name: name,
          os: os ?? existing.os,
          serverId: serverId ?? existing.serverId,
          discoveredAt: DateTime.now());
    } else {
      _pairedDevices.insert(
          0,
          DiscoveredDevice(
              ip: ip,
              name: name,
              os: os,
              serverId: serverId,
              discoveredAt: DateTime.now()));
    }

    await _persistPairedDevices();
  }

  Future<void> _persistPairedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _pairedDevices
        .map((d) => jsonEncode({
              'ip': d.ip,
              'name': d.name,
              'os': d.os,
              'serverId': d.serverId,
              'discoveredAt': d.discoveredAt.toIso8601String(),
            }))
        .toList();
    await prefs.setStringList('paired_devices', jsonList);
    notifyListeners();
  }

  Future<void> unpairDevice(String ip, {String? serverId}) async {
    try {
      _pairedDevices.removeWhere(
          (d) => d.ip == ip || (serverId != null && d.serverId == serverId));
      final key = serverId ?? ip;
      _tokens.remove(key);
      notifyListeners(); // 立即通知 UI 移除卡片，防止 index 越界或引用已删除数据

      await _persistPairedDevices();
      await _saveTokens();

      if (_lastConnectedIp == ip) {
        if (_channel != null) {
          try {
            _channel!.sink.add(jsonEncode({'type': 'unpair'}));
          } catch (_) {}
        }
        disconnect();
      }
    } catch (e) {
      addLog('解除配对失败: $e');
    }
  }

  Future<void> renamePairedDevice(String ip, String newName, {String? serverId}) async {
    // 优先使用 serverId 匹配设备
    final index = serverId != null
        ? _pairedDevices.indexWhere((d) => d.serverId == serverId)
        : _pairedDevices.indexWhere((d) => d.ip == ip);
    if (index != -1) {
      final d = _pairedDevices[index];
      _pairedDevices[index] = DiscoveredDevice(
          ip: d.ip,
          name: newName,
          os: d.os,
          serverId: d.serverId,
          discoveredAt: d.discoveredAt);
      await _persistPairedDevices();
      if (_lastConnectedIp == ip) {
        _remoteServerName = newName;
      }
      notifyListeners();
    }
  }

  Future<void> removePairedDevice(String ip, {String? serverId}) async {
    // 配对状态（Token）独立于收藏列表
    // 优先使用 serverId 匹配，兼容旧版无 ID 场景
    _pairedDevices.removeWhere((d) =>
        serverId != null ? d.serverId == serverId : d.ip == ip);
    await _persistPairedDevices();
  }

  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void setDeviceName(String name) async {
    _deviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
    notifyListeners();
  }

  // ==================== 日志逻辑 ====================

  void addLog(String log) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _logs.insert(0, '[$timeStr] $log');
    if (_logs.length > 200) _logs.removeRange(200, _logs.length);
    notifyListeners();
  }

  // ==================== 开关逻辑 ====================

  void toggleTheme(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', value);
    notifyListeners();
  }

  void setThemeColor(Color color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('seed_color', color.toARGB32());
    notifyListeners();
  }

  void setUseDynamicColor(bool value) async {
    _useDynamicColor = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_dynamic_color', value);
    notifyListeners();
  }

  void setInjectionMethod(String method) async {
    _injectionMethod = method;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('injection_method', method);
    notifyListeners();
  }

  Future<void> setPageTransitionType(String type) async {
    _pageTransitionType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('page_transition_type', type);
    notifyListeners();
  }

  Future<void> setUseSystemFont(bool value) async {
    _useSystemFont = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_system_font', value);
    notifyListeners();
  }

  void setBubbleColorType(String type) async {
    _bubbleColorType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bubble_color_type', type);
    notifyListeners();
  }

  // ==================== 设备发现 ====================

  Future<void> startDeviceDiscovery() async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredDevices.clear();
    notifyListeners();
    addLog('开始扫描局域网设备...');

    _performScan();

    int scanCount = 0;
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      scanCount++;
      if (scanCount >= 1) {
        // 3秒后停止扫描
        stopDeviceDiscovery();
        return;
      }
      _performScan();
    });
  }

  Future<void> _performScan() async {
    try {
      final data = utf8.encode('localtype_discovery');
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // 1. 发送到全局广播
      socket.send(data, InternetAddress('255.255.255.255'), 45678);

      // 2. 遍历所有网卡发送子网广播 (解决代理拦截)
      try {
        final interfaces = await NetworkInterface.list(
          includeLinkLocal: false,
          type: InternetAddressType.IPv4,
        );
        for (var iface in interfaces) {
          for (var addr in iface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              // 尝试发送到子网广播
              final broadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              socket.send(data, InternetAddress(broadcast), 45678);
            }
          }
        }
      } catch (e) {
        debugPrint('获取网卡列表失败: $e');
      }

      socket.listen((RawSocketEvent e) async {
        Datagram? d = socket.receive();
        if (d == null) return;

        String message = utf8.decode(d.data).trim();
        if (message.startsWith('localtype_server:')) {
          final content = message.substring('localtype_server:'.length);
          final parts = content.split('|');
          if (parts.isNotEmpty) {
            final ip = parts[0];
            final serverName = parts.length > 1 ? parts[1] : 'LocalType Server';
            final osName = parts.length > 2 ? parts[2] : 'desktop';
            final serverId = parts.length > 3 ? parts[3] : null;

            // 使用 serverId 去重，避免同一设备因 IP 变化出现多个条目
            final existingIdx = _discoveredDevices.indexWhere((dev) =>
                dev.ip == ip || (serverId != null && dev.serverId == serverId));
            if (existingIdx == -1) {
              _discoveredDevices.add(DiscoveredDevice(
                ip: ip,
                name: serverName,
                os: osName,
                serverId: serverId,
                discoveredAt: DateTime.now(),
              ));
              addLog(
                  '发现设备: $serverName ($ip) [$osName] ID: ${serverId ?? "NONE"}');
            } else {
              // 更新已存在设备的最新 IP 和信息
              _discoveredDevices[existingIdx] = DiscoveredDevice(
                ip: ip,
                name: serverName,
                os: osName,
                serverId: serverId,
                discoveredAt: DateTime.now(),
              );
            }
            notifyListeners();

            // 同步到已配对列表：优先使用 serverId 匹配
            final pairedIndex = serverId != null
                ? _pairedDevices.indexWhere((d) => d.serverId == serverId)
                : _pairedDevices.indexWhere((d) => d.ip == ip);
            if (pairedIndex != -1) {
              final p = _pairedDevices[pairedIndex];
              if (p.ip != ip || p.name != serverName ||
                  p.os != osName || p.serverId != serverId) {
                await _savePairedDevice(ip, serverName, osName, serverId);
              }
            }
          }
        }
      });

      Future.delayed(const Duration(seconds: 2), () {
        socket.close();
      });
    } catch (e) {
      addLog('扫描错误: $e');
    }
  }

  void stopDeviceDiscovery() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
    notifyListeners();
  }

  Future<void> discoverDevices() async {
    await startDeviceDiscovery();
  }

  // ==================== 连接逻辑 ====================

  Future<void> connect(String ip, {bool isRetry = false}) async {
    if (ip.isEmpty) {
      addLog('请输入 IP 地址');
      return;
    }

    if (!_isInitialized) {
      addLog('正在加载配置，请稍候...');
      return;
    }

    // 防止重复连接或正在连接中
    if (_status == ConnectionStatus.connected && _lastConnectedIp == ip) {
      return;
    }
    if (_status == ConnectionStatus.connecting && !isRetry) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (!isRetry) {
      _reconnectAttempts = 0;
    }

    _status = ConnectionStatus.connecting;
    _authStatus = AuthStatus.unauthenticated;
    notifyListeners();
    addLog('正在连接 wss://$ip:8765...');

    try {
      // 懒加载并复用 HttpClient，避免频繁创建导致 fd 泄露
      _client ??= HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true)
        ..connectionTimeout = const Duration(seconds: 10);

      // 确保之前的连接已关闭
      _channel?.sink.close();

      final webSocket =
          await WebSocket.connect('wss://$ip:8765', customClient: _client);
      _channel = IOWebSocketChannel(webSocket);

      _status = ConnectionStatus.connected;

      String nameToSave = '桌面端 ($ip)';
      String? serverId;
      String? os;
      final discoveredMatch = _discoveredDevices.where((d) => d.ip == ip);
      if (discoveredMatch.isNotEmpty) {
        final d = discoveredMatch.first;
        nameToSave = d.name;
        serverId = d.serverId;
        os = d.os;
      } else {
        final pairedMatch = _pairedDevices.where((d) => d.ip == ip);
        if (pairedMatch.isNotEmpty) {
          final d = pairedMatch.first;
          nameToSave = d.name;
          serverId = d.serverId;
          os = d.os;
        }
      }
      _remoteServerName = nameToSave;
      _remoteServerId = serverId;
      _remoteServerOs = os;

      // 如果有 Token 查找对应的
      String? matchedToken;
      if (serverId != null) {
        matchedToken = _tokens[serverId];
      }
      // 兼容旧版或无 ID 场景，尝试使用 IP 作为临时 key
      matchedToken ??= _tokens[ip];
      // 兼容从旧版本升级的情况
      matchedToken ??= _tokens['legacy_key'];

      _addSystemMessage('已连接到 $_remoteServerName');

      _lastConnectedIp = ip;
      _reconnectAttempts = 0;

      addLog('已连接到 $_remoteServerName');
      notifyListeners();

      _startHeartbeat();

      if (matchedToken != null) {
        _sendAuth(matchedToken);
      } else {
        _requestPairing();
      }

      // 此处不再自动保存

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          _status = ConnectionStatus.error;
          addLog('连接错误: $error');
          _cleanupConnection();
          _scheduleReconnect();
          notifyListeners();
        },
        onDone: () {
          if (_status != ConnectionStatus.disconnected) {
            addLog('连接意外断开');
            _status = ConnectionStatus.disconnected;
            _cleanupConnection();
            _scheduleReconnect();
          } else {
            addLog('已断开连接');
            _cleanupConnection();
          }
          notifyListeners();
        },
      );
    } catch (e) {
      _status = ConnectionStatus.error;
      addLog('连接失败: $e');
      _cleanupConnection();
      _scheduleReconnect();
      notifyListeners();
    }
  }

  Future<void> _handleMessage(dynamic message) async {
    try {
      final Map<String, dynamic> msg = jsonDecode(message);
      switch (msg['type']) {
        case 'pong':
          break;
        case 'pairingcoderequired':
          addLog('需要配对验证码，请查看电脑端弹窗');
          _authStatus = AuthStatus.pairingRequired;
          notifyListeners();
          if (onPairingRequired != null) {
            onPairingRequired!('请输入电脑端显示的验证码');
          }
          break;
        case 'pairingsuccess':
          final token = msg['token'];
          final serverOs = msg['os'];
          if (serverOs != null) _remoteServerOs = serverOs;

          final id = _remoteServerId ?? _lastConnectedIp!;
          await _saveToken(id, token);
          // 自动加入已配对设备列表以便管理
          await _savePairedDevice(
            _lastConnectedIp!,
            _remoteServerName ?? '桌面端 ($_lastConnectedIp)',
            _remoteServerOs, // 使用更新后的 OS
            _remoteServerId,
          );
          _authStatus = AuthStatus.authenticated;
          addLog('配对成功！');
          notifyListeners();
          break;
        case 'authsuccess':
          final serverOs = msg['os'];
          if (serverOs != null) _remoteServerOs = serverOs;

          _authStatus = AuthStatus.authenticated;
          // 确保认证成功的设备也在管理列表中
          if (_lastConnectedIp != null) {
            await _savePairedDevice(
              _lastConnectedIp!,
              _remoteServerName ?? '桌面端 ($_lastConnectedIp)',
              _remoteServerOs,
              _remoteServerId,
            );
          }
          addLog('认证成功');
          notifyListeners();
          break;
        case 'authfailed':
          addLog('认证失败，令牌已失效或设备已被移除');
          if (_remoteServerId != null) {
            _tokens.remove(_remoteServerId);
          }
          if (_lastConnectedIp != null) {
            _tokens.remove(_lastConnectedIp);
          }
          _saveTokens();
          disconnect(); // 直接断开，不再自动发起配对请求
          break;
        case 'unpaired':
          _addSystemMessage('连接已撤销或已解除配对');
          if (_remoteServerId != null) {
            _tokens.remove(_remoteServerId);
          }
          if (_lastConnectedIp != null) {
            _tokens.remove(_lastConnectedIp);
          }
          _saveTokens();
          disconnect();
          break;
        case 'ack':
          final msgId = msg['msg_id'];
          final index = _messages.indexWhere((m) => m.id == msgId);
          if (index != -1) {
            _messages[index].status = MessageStatus.acked;
            notifyListeners();
          }
          break;
        case 'error':
          addLog('服务端错误: ${msg['message']}');
          break;
        default:
          addLog('收到: $message');
      }
    } catch (_) {
      addLog('收到: $message');
    }
  }

  void _sendAuth(String token) {
    if (_channel == null) return;
    addLog('正在认证...');
    _channel!.sink.add(jsonEncode({
      'type': 'auth',
      'device_id': _deviceId,
      'token': token,
      'os': Platform.operatingSystem
    }));
  }

  void _requestPairing() {
    if (_channel == null) return;
    addLog('请求配对...');
    _channel!.sink.add(jsonEncode({
      'type': 'requestpairing',
      'device_name': _deviceName,
      'device_id': _deviceId,
      'os': Platform.operatingSystem
    }));
  }

  void submitPairingCode(String code) {
    if (_channel == null) return;
    addLog('提交验证码: $code');
    _channel!.sink.add(jsonEncode({
      'type': 'verifypairing',
      'device_id': _deviceId,
      'device_name': _deviceName,
      'code': code,
      'os': Platform.operatingSystem
    }));
  }

  Future<void> _saveToken(String key, String token) async {
    _tokens[key] = token;
    await _saveTokens();
  }

  Future<void> _saveTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_tokens', jsonEncode(_tokens));
  }

  void disconnect() {
    if (_status == ConnectionStatus.disconnected) return;

    _stopReconnect();
    _addSystemMessage('已断开连接');
    _channel?.sink.close();
    _cleanupConnection();
    _status = ConnectionStatus.disconnected;
    _authStatus = AuthStatus.unauthenticated;
    _lastConnectedIp = null;
    _remoteServerName = null;
    _reconnectAttempts = 0;
    notifyListeners();
  }

  void _cleanupConnection() {
    _stopHeartbeat();
    _channel = null;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_status == ConnectionStatus.connected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          addLog('心跳失败: $e');
          disconnect();
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= 5) {
      addLog('达到最大重连次数，已停止');
      _status = ConnectionStatus.disconnected;
      _remoteServerName = null;
      _lastConnectedIp = null;
      _authStatus = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    if (_lastConnectedIp == null) return;

    const delaySeconds = 2;
    addLog('将在 ${delaySeconds}s 后重连...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: delaySeconds), () {
      _reconnectAttempts++;
      connect(_lastConnectedIp!, isRetry: true);
    });
  }

  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ==================== 文字发送 ====================

  void sendText() {
    if (_status != ConnectionStatus.connected ||
        _authStatus != AuthStatus.authenticated) {
      if (_authStatus != AuthStatus.authenticated &&
          _status == ConnectionStatus.connected) {
        addLog('等待认证完成...');
      }
      return;
    }

    final text = textController.text;
    if (text.isEmpty) return;

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();

    // UI 先上屏
    final messageObj = MessageModel(
      id: msgId,
      text: text,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    _messages.insert(0, messageObj);
    notifyListeners();

    final message = jsonEncode({
      'type': 'send',
      'content': text,
      'method': _injectionMethod,
      'msg_id': msgId,
    });

    try {
      _channel!.sink.add(message);

      // 更新状态为已送出（单勾）
      messageObj.status = MessageStatus.sent;

      addLog('已发送: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}');
      _addToHistory(text);
      _addCharCount(text.length);
      textController.clear();
      notifyListeners();
    } catch (e) {
      messageObj.status = MessageStatus.error;
      addLog('发送失败: $e');
      notifyListeners();
    }
  }

  void sendDirectText(String text) {
    if (_status != ConnectionStatus.connected ||
        _authStatus != AuthStatus.authenticated) {
      return;
    }
    if (text.isEmpty) {
      return;
    }

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();

    // UI 先上屏
    final messageObj = MessageModel(
      id: msgId,
      text: text,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    _messages.insert(0, messageObj);
    notifyListeners();

    final message = jsonEncode({
      'type': 'send',
      'content': text,
      'method': _injectionMethod,
      'msg_id': msgId,
    });

    try {
      _channel!.sink.add(message);
      messageObj.status = MessageStatus.sent;

      addLog(
          '快捷发送: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}');
      _addToHistory(text);
      _addCharCount(text.length);
      notifyListeners();
    } catch (e) {
      messageObj.status = MessageStatus.error;
      addLog('发送失败: $e');
      notifyListeners();
    }
  }

  void _addToHistory(String text) async {
    _sendHistory.remove(text);
    _sendHistory.insert(0, text);
    if (_sendHistory.length > _maxHistory) {
      _sendHistory = _sendHistory.sublist(0, _maxHistory);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('send_history', _sendHistory);
    notifyListeners();
  }

  void clearHistory() async {
    _sendHistory.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('send_history');
    notifyListeners();
  }

  // ==================== 快捷短语与统计 ====================

  Future<void> addPhrase(String label, String content) async {
    final phrase = QuickPhrase(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      content: content,
    );
    _quickPhrases.add(phrase);
    await _savePhrases();
    notifyListeners();
  }

  Future<void> updatePhrase(String id, String label, String content) async {
    final index = _quickPhrases.indexWhere((p) => p.id == id);
    if (index != -1) {
      _quickPhrases[index] = QuickPhrase(
        id: id,
        label: label,
        content: content,
      );
      await _savePhrases();
      notifyListeners();
    }
  }

  Future<void> removePhrase(String id) async {
    _quickPhrases.removeWhere((p) => p.id == id);
    await _savePhrases();
    notifyListeners();
  }

  Future<void> removePhrases(List<String> ids) async {
    _quickPhrases.removeWhere((p) => ids.contains(p.id));
    await _savePhrases();
    notifyListeners();
  }

  Future<void> _savePhrases() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_quickPhrases.map((p) => p.toJson()).toList());
    await prefs.setString('quick_phrases', json);
  }

  void _addCharCount(int count) async {
    _totalChars += count;
    final todayKey = _getTodayKey();
    if (todayKey != _todayDateKey) {
      _todayDateKey = todayKey;
      _todayChars = 0;
    }
    _todayChars += count;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('total_chars', _totalChars);
    await prefs.setInt('today_chars_$_todayDateKey', _todayChars);
    notifyListeners();
  }

  // ==================== 更新检查 ====================

  Future<void> checkForUpdate({bool silent = false}) async {
    _isCheckingUpdate = true;
    if (!silent) notifyListeners();

    try {
      final info = await UpdateService.checkForUpdate();
      _updateInfo = info;
    } catch (e) {
      if (!silent) {
        addLog('检查更新失败: $e');
      }
      _updateInfo = null;
    }

    _isCheckingUpdate = false;
    notifyListeners();
  }

  Future<void> skipCurrentUpdate() async {
    if (_updateInfo != null && _updateInfo!.available) {
      await UpdateService.skipVersion(_updateInfo!.latestVersion);
      _updateInfo = null;
      notifyListeners();
    }
  }

  void _addSystemMessage(String text) {
    _messages.insert(
      0,
      MessageModel(
        id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
        text: text,
        timestamp: DateTime.now(),
        isSystem: true,
      ),
    );
    notifyListeners();
  }
}
