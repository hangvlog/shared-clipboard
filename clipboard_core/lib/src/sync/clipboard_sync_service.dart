import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import '../config.dart';
import '../models/clipboard_item.dart';
import '../models/device_info.dart';

/// 连接状态
enum SyncConnectionState { disconnected, connecting, connected }

/// Socket.IO 实时同步服务
///
/// 与桌面端 TypeScript 的 socketService.ts 保持完全一致的事件协议：
/// - register_device：注册设备（关联 user_id）
/// - clipboard_sync：剪贴板数据实时广播
class ClipboardSyncService {
  final ClipboardConfig config;
  final DeviceInfo deviceInfo;

  sio.Socket? _socket;
  SyncConnectionState _connectionState = SyncConnectionState.disconnected;

  final _connectionStateController = StreamController<SyncConnectionState>.broadcast();
  final _clipboardSyncController = StreamController<ClipboardItem>.broadcast();

  /// 连接状态变化流
  Stream<SyncConnectionState> get connectionState => _connectionStateController.stream;

  /// 接收到其他设备剪贴板同步数据的流
  Stream<ClipboardItem> get onClipboardSync => _clipboardSyncController.stream;

  /// 当前连接状态
  SyncConnectionState get currentState => _connectionState;

  /// 是否已连接
  bool get isConnected => _connectionState == SyncConnectionState.connected;

  ClipboardSyncService({
    required this.config,
    required this.deviceInfo,
  });

  /// 连接到 Socket.IO 服务器
  ///
  /// 对应桌面端 socketService.connect(token)
  void connect() {
    if (_socket?.connected == true) return;

    _updateState(SyncConnectionState.connecting);

    // 断开旧连接
    _socket?.dispose();

    _socket = sio.io(
      config.wsBaseUrl,
      sio.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.maxFinite.toInt())
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .build(),
    );

    _socket!.onConnect((_) {
      _updateState(SyncConnectionState.connected);
      _registerDevice();
    });

    _socket!.onDisconnect((_) {
      _updateState(SyncConnectionState.disconnected);
    });

    _socket!.onConnectError((error) {
      _updateState(SyncConnectionState.disconnected);
    });

    // 监听剪贴板同步事件（与桌面端 'clipboard_sync' 事件一致）
    _socket!.on('clipboard_sync', (data) {
      try {
        if (data is Map<String, dynamic>) {
          final type = data['type'] as String?;
          final itemData = data['item'] as Map<String, dynamic>?;
          if (type == 'clipboard_sync' && itemData != null) {
            final item = ClipboardItem.fromJson(itemData);
            _clipboardSyncController.add(item);
          }
        }
      } catch (e) {
        // 解析失败静默处理，与桌面端 catch 行为一致
      }
    });

    _socket!.connect();
  }

  /// 注册设备到服务器（关联 user_id）
  ///
  /// 对应桌面端 socketService.registerDevice(token)
  void _registerDevice() {
    _socket?.emitWithAck('register_device', {
      'deviceId': deviceInfo.deviceId,
      'deviceType': deviceInfo.deviceType,
      'deviceName': deviceInfo.deviceName,
      'platform': deviceInfo.platform,
      'token': config.token,
    });
  }

  /// 广播剪贴板内容到其他设备
  ///
  /// 对应桌面端 socketService.emit('clipboard_sync', { item })
  void broadcastClipboardItem(ClipboardItem item) {
    if (_socket?.connected != true) return;
    _socket!.emit('clipboard_sync', {'item': item.toJson()});
  }

  /// 断开连接
  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _updateState(SyncConnectionState.disconnected);
  }

  void _updateState(SyncConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _clipboardSyncController.close();
  }
}
