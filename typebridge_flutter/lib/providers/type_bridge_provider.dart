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

/// 已发现的设备信息
class DiscoveredDevice {
  final String ip;
  final String name;
  final DateTime discoveredAt;

  DiscoveredDevice({
    required this.ip,
    required this.name,
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

/// TypeBridge 核心状态管理
/// 负责 WebSocket 连接、认证、文本发送、设备发现、统计及生命周期管理
class TypeBridgeProvider extends ChangeNotifier with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  AuthStatus _authStatus = AuthStatus.unauthenticated;
  final List<String> _logs = [];
  final TextEditingController ipController = TextEditingController();
  final TextEditingController textController = TextEditingController();

  bool _isRealtime = false;
  bool _isDarkMode = false;
  String? _deviceId;
  String? _deviceName;
  String? _authToken;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _debounceTimer;
  int _reconnectAttempts = 0;
  String? _lastConnectedIp;
  String _injectionMethod = 'unicode';

  // --- V1.1 新增：设备发现 ---
  final List<DiscoveredDevice> _discoveredDevices = [];
  bool _isScanning = false;
  Timer? _scanTimer;

  // --- V1.1 新增：历史记录 ---
  List<String> _sendHistory = [];
  static const int _maxHistory = 10;

  // --- V1.1 新增：快捷短语 ---
  List<QuickPhrase> _quickPhrases = [];

  // --- V1.1 新增：字数统计（仅聊天模式） ---
  int _totalChars = 0;
  int _todayChars = 0;
  String _todayDateKey = '';

  /// 配对对话框回调
  Function(String)? onPairingRequired;

  // Getters
  ConnectionStatus get status => _status;
  ConnectionStatus get connectionStatus =>
      _status; // Alias for UI compatibility
  AuthStatus get authStatus => _authStatus;
  List<String> get logs => _logs;
  bool get isRealtime => _isRealtime;
  bool get isDarkMode => _isDarkMode;
  String get injectionMethod => _injectionMethod;
  String? get connectedIp => _lastConnectedIp;
  String? get deviceName => _deviceName;
  List<DiscoveredDevice> get discoveredDevices => _discoveredDevices;
  bool get isScanning => _isScanning;
  List<String> get sendHistory => _sendHistory;
  List<QuickPhrase> get quickPhrases => _quickPhrases;
  int get totalChars => _totalChars;
  int get todayChars => _todayChars;

  TypeBridgeProvider() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHeartbeat();
    _stopReconnect();
    _debounceTimer?.cancel();
    _scanTimer?.cancel();
    _channel?.sink.close();
    ipController.dispose();
    textController.dispose();
    super.dispose();
  }

  /// NOTE: 生命周期监听 —— 从后台切回前台时立即检查连接状态
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      addLog('应用回到前台，检查连接状态...');
      if (_lastConnectedIp != null && _status != ConnectionStatus.connected) {
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
    _injectionMethod = prefs.getString('injection_method') ?? 'unicode';

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

    // 加载历史记录
    final historyJson = prefs.getStringList('send_history');
    if (historyJson != null) {
      _sendHistory = historyJson;
    }

    // 加载快捷短语
    final phrasesJson = prefs.getString('quick_phrases');
    if (phrasesJson != null) {
      final List<dynamic> decoded = jsonDecode(phrasesJson);
      _quickPhrases = decoded.map((e) => QuickPhrase.fromJson(e)).toList();
    }

    // 加载字数统计
    _totalChars = prefs.getInt('total_chars') ?? 0;
    _todayDateKey = _getTodayKey();
    _todayChars = prefs.getInt('today_chars_$_todayDateKey') ?? 0;

    notifyListeners();
  }

  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // ==================== 日志 ====================

  void addLog(String log) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _logs.insert(0, '[$timeStr] $log');
    if (_logs.length > 200) {
      _logs.removeRange(200, _logs.length);
    }
    notifyListeners();
  }

  // ==================== 主题 / 注入方式 ====================

  void toggleRealtime(bool value) {
    _isRealtime = value;
    notifyListeners();
  }

  void toggleTheme(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', value);
    notifyListeners();
  }

  void setInjectionMethod(String method) async {
    _injectionMethod = method;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('injection_method', method);
    notifyListeners();
  }

  // ==================== 设备发现（Radar） ====================

  /// 开始扫描局域网设备，持续扫描直到手动停止或超时
  Future<void> startDeviceDiscovery() async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredDevices.clear();
    notifyListeners();
    addLog('开始扫描局域网设备...');

    _performScan();

    // 每 3 秒重复扫描一次，持续 15 秒
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
        final data = utf8.encode('typebridge_discovery');
        socket.send(data, InternetAddress('255.255.255.255'), 45678);

        socket.listen((RawSocketEvent e) {
          Datagram? d = socket.receive();
          if (d == null) return;

          String message = utf8.decode(d.data).trim();
          if (message.startsWith('typebridge_server:')) {
            final parts = message.split(':');
            final ip = parts[1];
            // NOTE: 避免重复添加同一设备
            if (!_discoveredDevices.any((dev) => dev.ip == ip)) {
              final serverName = parts.length > 2
                  ? parts.sublist(2).join(':')
                  : 'TypeBridge Server';
              _discoveredDevices.add(DiscoveredDevice(
                ip: ip,
                name: serverName,
                discoveredAt: DateTime.now(),
              ));
              addLog('发现设备: $serverName ($ip)');
              notifyListeners();
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

  /// V1 兼容：简化版发现，仅填充 IP
  Future<void> discoverDevices() async {
    await startDeviceDiscovery();
  }

  // ==================== WebSocket 连接 ====================

  Future<void> connect(String ip) async {
    if (ip.isEmpty) {
      addLog('请输入 IP 地址');
      return;
    }

    _stopReconnect();

    _status = ConnectionStatus.connecting;
    _authStatus = AuthStatus.unauthenticated;
    notifyListeners();
    addLog('正在连接 wss://$ip:8765...');

    try {
      final HttpClient client = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true)
        ..connectionTimeout = const Duration(seconds: 10);

      final webSocket =
          await WebSocket.connect('wss://$ip:8765', customClient: client);
      _channel = IOWebSocketChannel(webSocket);

      _status = ConnectionStatus.connected;
      _lastConnectedIp = ip;
      _reconnectAttempts = 0;
      addLog('已连接到 $ip（安全连接）');
      notifyListeners();

      _startHeartbeat();

      if (_authToken != null) {
        _sendAuth();
      } else {
        _requestPairing();
      }

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
          addLog('认证失败，令牌可能已过期');
          _authToken = null;
          _saveToken('');
          _requestPairing();
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
    _channel!.sink.add(jsonEncode(
        {'type': 'auth', 'device_id': _deviceId, 'token': _authToken}));
  }

  void _requestPairing() {
    if (_channel == null) return;
    addLog('请求配对...');
    _channel!.sink.add(jsonEncode({
      'type': 'requestpairing',
      'device_name': _deviceName,
      'device_id': _deviceId
    }));
  }

  void submitPairingCode(String code) {
    if (_channel == null) return;
    addLog('提交验证码: $code');
    _channel!.sink.add(jsonEncode({
      'type': 'verifypairing',
      'device_id': _deviceId,
      'device_name': _deviceName,
      'code': code
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _authToken = null;
    addLog('配对信息已清除');
    notifyListeners();
  }

  void disconnect() {
    _stopReconnect();
    addLog('正在断开...');
    if (_channel != null) {
      _channel!.sink.close();
    }
    _cleanupConnection();
    _status = ConnectionStatus.disconnected;
    _authStatus = AuthStatus.unauthenticated;
    _lastConnectedIp = null;
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

  /// NOTE: 指数退避重连策略，带 20% 随机抖动
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

  // ==================== 发送文本 ====================

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
    if (text.isEmpty && !_isRealtime) return;

    final message = jsonEncode({
      'type': 'send',
      'mode': _isRealtime ? 'realtime' : 'chat',
      'content': text,
      'method': _injectionMethod,
    });

    try {
      _channel!.sink.add(message);
      if (!_isRealtime) {
        addLog(
            '已发送: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}');

        // V1.1: 记录历史与统计（仅聊天模式）
        _addToHistory(text);
        _addCharCount(text.length);

        textController.clear();
      }
    } catch (e) {
      addLog('发送失败: $e');
    }
  }

  /// 直接发送指定文本（用于短语和历史记录快捷发送）
  void sendDirectText(String text) {
    if (_status != ConnectionStatus.connected ||
        _authStatus != AuthStatus.authenticated) {
      return;
    }
    if (text.isEmpty) return;

    final message = jsonEncode({
      'type': 'send',
      'mode': 'chat',
      'content': text,
      'method': _injectionMethod,
    });

    try {
      _channel!.sink.add(message);
      addLog(
          '快捷发送: ${text.length > 20 ? '${text.substring(0, 20)}...' : text}');
      _addToHistory(text);
      _addCharCount(text.length);
    } catch (e) {
      addLog('发送失败: $e');
    }
  }

  void sendRealtimeText(String text) {
    if (!_isRealtime) return;

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      sendText();
    });
  }

  // ==================== 历史记录 ====================

  void _addToHistory(String text) async {
    // 避免重复记录完全相同的内容
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

  // ==================== 快捷短语 ====================

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

  Future<void> removePhrase(String id) async {
    _quickPhrases.removeWhere((p) => p.id == id);
    await _savePhrases();
    notifyListeners();
  }

  Future<void> _savePhrases() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_quickPhrases.map((p) => p.toJson()).toList());
    await prefs.setString('quick_phrases', json);
  }

  // ==================== 字数统计 ====================

  void _addCharCount(int count) async {
    _totalChars += count;

    // 检测日期是否变更
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
}
