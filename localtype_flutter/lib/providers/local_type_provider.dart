import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

enum AuthStatus { authenticated, unauthenticated, pairingRequired }

/// 已发现/已配对的设备信息
class DiscoveredDevice {
  final String ip;
  final String name;
  final String? os;
  final DateTime discoveredAt;

  DiscoveredDevice({
    required this.ip,
    required this.name,
    this.os,
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
  Color _seedColor = const Color(0xFF2563EB);
  String? _deviceId;
  String? _deviceName; // 本地设备名称
  String? _remoteServerName; // 已连接的服务端名称
  String? _authToken;

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

  // --- V1.2 聊天流 ---
  final List<MessageModel> _messages = [];

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
  Color get seedColor => _seedColor;
  bool get useDynamicColor => _useDynamicColor;
  String get pageTransitionType => _pageTransitionType;
  String get bubbleColorType => _bubbleColorType;
  List<MessageModel> get messages => List.unmodifiable(_messages);

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
    _authToken = prefs.getString('auth_token');
    _deviceId = prefs.getString('device_id');
    _deviceName = prefs.getString('device_name');
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
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

    // Load Paired Devices
    await _loadPairedDevices();

    _isInitialized = true;
    notifyListeners();
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
            discoveredAt:
                DateTime.tryParse(data['discoveredAt'] ?? '') ?? DateTime.now(),
          );
        }).toList();
      } catch (e) {
        addLog('加载已配对设备出错: $e');
      }
    }
  }

  Future<void> toggleFavorite(String ip, String name, String os) async {
    final isSaved = _pairedDevices.any((d) => d.ip == ip);
    if (isSaved) {
      await removePairedDevice(ip);
      addLog('已从收藏库移除: $name');
    } else {
      await _savePairedDevice(ip, name, os);
      addLog('已加入收藏库: $name');
    }
  }

  Future<void> _savePairedDevice(String ip, String name, String os) async {
    final index = _pairedDevices.indexWhere((d) => d.ip == ip);
    if (index != -1) {
      _pairedDevices[index] = DiscoveredDevice(
          ip: ip, name: name, os: os, discoveredAt: DateTime.now());
    } else {
      _pairedDevices.insert(
          0,
          DiscoveredDevice(
              ip: ip, name: name, os: os, discoveredAt: DateTime.now()));
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonList = _pairedDevices
        .map((d) => jsonEncode({
              'ip': d.ip,
              'name': d.name,
              'os': d.os,
              'discoveredAt': d.discoveredAt.toIso8601String(),
            }))
        .toList();
    await prefs.setStringList('paired_devices', jsonList);
    notifyListeners();
  }

  Future<void> removePairedDevice(String ip) async {
    // 配对状态（Token）独立于收藏列表

    _pairedDevices.removeWhere((d) => d.ip == ip);
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _pairedDevices
        .map((d) => jsonEncode({
              'ip': d.ip,
              'name': d.name,
              'os': d.os,
              'discoveredAt': d.discoveredAt.toIso8601String(),
            }))
        .toList();
    await prefs.setStringList('paired_devices', jsonList);
    notifyListeners();
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
      if (scanCount >= 5) {
        stopDeviceDiscovery();
        return;
      }
      _performScan();
    });
  }

  void _performScan() {
    try {
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
        socket.broadcastEnabled = true;
        final data = utf8.encode('localtype_discovery');
        socket.send(data, InternetAddress('255.255.255.255'), 45678);

        socket.listen((RawSocketEvent e) {
          Datagram? d = socket.receive();
          if (d == null) return;

          String message = utf8.decode(d.data).trim();
          if (message.startsWith('localtype_server:')) {
            final content = message.substring('localtype_server:'.length);
            final parts = content.split('|');
            if (parts.isNotEmpty) {
              final ip = parts[0];
              final serverName =
                  parts.length > 1 ? parts[1] : 'LocalType Server';
              final osName = parts.length > 2 ? parts[2] : 'desktop';

              if (!_discoveredDevices.any((dev) => dev.ip == ip)) {
                _discoveredDevices.add(DiscoveredDevice(
                  ip: ip,
                  name: serverName,
                  os: osName,
                  discoveredAt: DateTime.now(),
                ));
                addLog('发现设备: $serverName ($ip) [$osName]');
                notifyListeners();

                // 如果发现的设备详情有更新，同步到已配对列表
                final pairedIndex =
                    _pairedDevices.indexWhere((d) => d.ip == ip);
                if (pairedIndex != -1) {
                  final p = _pairedDevices[pairedIndex];
                  if (p.name != serverName || p.os != osName) {
                    _savePairedDevice(ip, serverName, osName);
                  }
                }
              }
            }
          }
        });

        Future.delayed(const Duration(seconds: 2), () {
          socket.close();
        });
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

  Future<void> connect(String ip) async {
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
    if (_status == ConnectionStatus.connecting) {
      return;
    }

    _stopReconnect();

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

      // 确定远程设备显示名称
      String nameToSave = '桌面端 ($ip)';
      final discoveredMatch = _discoveredDevices.where((d) => d.ip == ip);
      if (discoveredMatch.isNotEmpty) {
        nameToSave = discoveredMatch.first.name;
      } else {
        final pairedMatch = _pairedDevices.where((d) => d.ip == ip);
        if (pairedMatch.isNotEmpty) nameToSave = pairedMatch.first.name;
      }
      _remoteServerName = nameToSave;

      // 会话隔离逻辑：如果 IP 变了，清空消息列表
      if (_lastConnectedIp != null && _lastConnectedIp != ip) {
        _messages.clear();
        addLog('切换目标设备，已开启新会话');
      }

      _addSystemMessage('已连接到 $_remoteServerName');

      _lastConnectedIp = ip;
      _reconnectAttempts = 0;

      addLog('已连接到 $_remoteServerName');
      notifyListeners();

      _startHeartbeat();

      if (_authToken != null) {
        _sendAuth();
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

  void _handleMessage(dynamic message) {
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
          _authToken = msg['token'];
          _saveToken(_authToken!);
          _authStatus = AuthStatus.authenticated;
          addLog('配对成功！');
          notifyListeners();
          break;
        case 'authsuccess':
          _authStatus = AuthStatus.authenticated;
          addLog('认证成功');
          notifyListeners();
          break;
        case 'authfailed':
          addLog('认证失败，令牌已失效或设备已被移除');
          _authToken = null;
          _saveToken('');
          disconnect(); // 直接断开，不再自动发起配对请求
          break;
        case 'unpaired':
          _addSystemMessage('连接已撤销或已解除配对');
          _authToken = null;
          _saveToken('');
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

  void _sendAuth() {
    if (_channel == null) return;
    addLog('正在认证...');
    _channel!.sink.add(jsonEncode({
      'type': 'auth',
      'device_id': _deviceId,
      'token': _authToken,
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

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token.isEmpty) {
      prefs.remove('auth_token');
    } else {
      prefs.setString('auth_token', token);
    }
  }

  Future<void> clearPairingData() async {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({'type': 'unpair'}));
        addLog('已向服务端发送解除配对请求');
      } catch (e) {
        addLog('发送解除配对请求失败: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _authToken = null;
    addLog('本地配对信息已清除');
    // 给异步发送留一点时间
    await Future.delayed(const Duration(milliseconds: 300));
    disconnect();
    notifyListeners();
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
    if (_reconnectAttempts >= 8) {
      addLog('达到最大重连次数，已停止');
      return;
    }

    if (_lastConnectedIp == null) return;

    final baseDelay = min(pow(2, _reconnectAttempts).toInt(), 60);
    final jitter = (baseDelay * 0.2 * Random().nextDouble()).toInt();
    final delaySeconds = baseDelay + jitter;
    addLog('将在 ${delaySeconds}s 后重连...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectAttempts++;
      connect(_lastConnectedIp!);
    });
  }

  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
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
