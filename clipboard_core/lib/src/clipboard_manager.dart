import 'dart:async';
import 'models/clipboard_item.dart';
import 'models/device_info.dart';
import 'api/clipboard_api_client.dart';
import 'sync/clipboard_sync_service.dart';
import 'crypto/clipboard_crypto_service.dart';
import 'platform/platform_adapter.dart';
import 'config.dart';

/// 剪贴板管理器
///
/// 整合 API 客户端、Socket.IO 同步、加密服务和平台适配器，
/// 提供与桌面端 clipboardStore.ts 完全对齐的业务逻辑。
class ClipboardManager {
  final ClipboardConfig config;
  final PlatformAdapter platform;

  late final ClipboardApiClient _apiClient;
  late final ClipboardSyncService _syncService;
  final ClipboardCryptoService _cryptoService = ClipboardCryptoService();

  /// 当前剪贴板条目列表
  List<ClipboardItem> _items = [];

  /// 条目变化通知流
  final _itemsController = StreamController<List<ClipboardItem>>.broadcast();
  Stream<List<ClipboardItem>> get itemsStream => _itemsController.stream;

  /// 当前条目列表
  List<ClipboardItem> get items => List.unmodifiable(_items);

  /// 同步连接状态流
  Stream<SyncConnectionState> get connectionState =>
      _syncService.connectionState;

  /// 是否已连接
  bool get isConnected => _syncService.isConnected;

  /// 设备信息
  late final DeviceInfo _deviceInfo;

  StreamSubscription? _syncSubscription;
  bool _suspended = false;
  bool _disposed = false;

  ClipboardManager({required this.config, required this.platform}) {
    _deviceInfo = DeviceInfo(
      deviceId: platform.getDeviceId(),
      deviceType: platform.getDeviceType(),
      deviceName: platform.getDeviceName(),
      platform: platform.getPlatformName(),
    );

    _apiClient = ClipboardApiClient(config: config);
    _syncService = ClipboardSyncService(
      config: config,
      deviceInfo: _deviceInfo,
    );
  }

  /// 初始化管理器
  ///
  /// 对应桌面端 clipboardStore.init()：
  /// 1. 初始化本地缓存并立即加载（瞬间显示）
  /// 2. 异步增量同步服务端数据
  /// 3. 建立 Socket.IO 连接
  /// 4. 监听同步事件
  Future<void> init() async {
    // 1. 初始化本地缓存
    await platform.initStorage();
    final localItems = await platform.getAllCachedItems();
    if (_disposed) return;
    if (localItems.isNotEmpty) {
      _items = localItems;
      if (!_disposed) _itemsController.add(_items);
    }

    // 2. 后台增量同步
    syncWithServer().catchError((e) {
      // 同步失败不影响使用（本地缓存仍可用）
    });

    // 3. 建立实时连接
    if (!_suspended && !_disposed) _syncService.connect();

    // 4. 监听其他设备的同步事件
    _syncSubscription = _syncService.onClipboardSync.listen(_handleRemoteSync);
  }

  void suspend() {
    _suspended = true;
    _syncService.disconnect();
  }

  Future<void> resume() async {
    if (_disposed || !_suspended) return;
    _suspended = false;
    _syncService.connect();
    await syncWithServer();
  }

  /// 增量同步服务端数据
  ///
  /// 对应桌面端 clipboardStore.syncWithServer()
  Future<void> syncWithServer() async {
    if (_disposed || _suspended) return;
    final result = await _apiClient.sync();
    if (_disposed || _suspended) return;
    final decrypted = await _decryptItems(result.items);
    if (_disposed || _suspended) return;
    await platform.replaceAllCached(decrypted);
    if (_disposed || _suspended) return;
    _items = decrypted;
    await platform.setLastSyncTime(result.syncedAt);
    if (!_disposed) _itemsController.add(_items);
  }

  /// 添加剪贴板条目（文本）
  ///
  /// 对应桌面端 clipboardStore.addItem()
  Future<void> addTextItem(String content) async {
    if (_disposed || _suspended) return;
    if (content.isEmpty || content.length > config.maxContentLength) return;

    // 去重：与最近一条相同则跳过
    if (_items.isNotEmpty && _items.first.content == content) return;

    String sendContent = content;
    bool encrypted = false;
    String? contentHash;

    // 端到端加密
    if (_cryptoService.hasKey) {
      try {
        sendContent = _cryptoService.encryptText(content);
        contentHash = ClipboardCryptoService.generateContentHash(content);
        encrypted = true;
      } catch (_) {
        // 加密失败回退明文
      }
    }

    final serverItem = await _apiClient.addItem(
      content: sendContent,
      contentType: 'text',
      deviceId: _deviceInfo.deviceId,
      deviceName: _deviceInfo.deviceName,
      encrypted: encrypted,
      contentHash: contentHash,
    );

    if (_disposed) return;
    // 本地用明文显示
    final localItem = serverItem.copyWith(content: content, encrypted: false);

    _items.insert(0, localItem);
    if (_items.length > config.maxHistoryCount) {
      _items = _items.sublist(0, config.maxHistoryCount);
    }
    if (!_disposed) _itemsController.add(_items);

    // 缓存到本地
    await platform.upsertItems([localItem]);

    // 广播加密数据给其他设备
    _syncService.broadcastClipboardItem(serverItem);

    // 更新去重标记
  }

  /// 添加图片条目
  ///
  /// 对应桌面端 clipboardStore.addImageItem()
  Future<void> addImageItem(
    String imageContent, {
    String? preview,
    String? imageUrl,
  }) async {
    if (_disposed || _suspended) return;
    String sendContent = imageContent;
    String? sendPreview = preview;
    bool encrypted = false;
    String? contentHash;

    if (_cryptoService.hasKey) {
      try {
        sendContent = _cryptoService.encryptText(imageContent);
        if (preview != null) {
          sendPreview = _cryptoService.encryptText(preview);
        }
        contentHash = ClipboardCryptoService.generateContentHash(imageContent);
        encrypted = true;
      } catch (_) {}
    }

    final serverItem = await _apiClient.addItem(
      content: sendContent,
      contentType: 'image',
      deviceId: _deviceInfo.deviceId,
      deviceName: _deviceInfo.deviceName,
      preview: sendPreview,
      imageUrl: imageUrl,
      encrypted: encrypted,
      contentHash: contentHash,
    );

    if (_disposed) return;
    final localItem = serverItem.copyWith(
      content: imageContent,
      preview: preview,
      encrypted: false,
    );

    _items.insert(0, localItem);
    if (_items.length > config.maxHistoryCount) {
      _items = _items.sublist(0, config.maxHistoryCount);
    }
    if (!_disposed) _itemsController.add(_items);
    await platform.upsertItems([localItem]);
    _syncService.broadcastClipboardItem(serverItem);
  }

  /// 删除条目
  Future<void> deleteItem(String id) async {
    if (_disposed) return;
    await _apiClient.deleteItem(id);
    if (_disposed) return;
    _items.removeWhere((item) => item.id == id);
    if (!_disposed) _itemsController.add(_items);
    await platform.deleteCachedItem(id);
  }

  /// 清空历史
  Future<void> clearHistory() async {
    if (_disposed) return;
    await _apiClient.clearHistory();
    if (_disposed) return;
    _items.clear();
    if (!_disposed) _itemsController.add(_items);
    await platform.clearAllCached();
  }

  /// 复制内容到系统剪贴板
  ///
  /// 对应桌面端 clipboardStore.copyToClipboard()
  Future<void> copyToClipboard(ClipboardItem item) async {
    if (_disposed || item.encrypted) return;
    if (item.contentType == 'text' || item.contentType == 'rich') {
      await platform.writeClipboardText(item.content);
    }
    // 图片类型暂不自动写入剪贴板（移动端限制）
  }

  /// 设置加密密钥
  Future<void> setEncryptionKey(String password, String username) async {
    await _cryptoService.deriveKeyFromUsername(password, username);
    await syncWithServer();
  }

  /// 清除加密密钥
  void clearEncryptionKey() {
    _cryptoService.clearKey();
  }

  /// 处理远程同步事件
  Future<void> _handleRemoteSync(ClipboardItem rawItem) async {
    // 避免重复
    if (_items.any((i) => i.id == rawItem.id)) return;

    if (_disposed || _suspended) return;
    final item = await _decryptItem(rawItem);
    if (_disposed || _suspended) return;

    _items.insert(0, item);
    if (_items.length > config.maxHistoryCount) {
      _items = _items.sublist(0, config.maxHistoryCount);
    }
    if (!_disposed) _itemsController.add(_items);
    await platform.upsertItems([item]);

    // 来自其他设备的文本自动写入剪贴板
    if (item.deviceId != _deviceInfo.deviceId &&
        item.contentType == 'text' &&
        !item.encrypted &&
        !_disposed &&
        !_suspended) {
      await platform.writeClipboardText(item.content);
    }
  }

  /// 解密单条记录
  Future<ClipboardItem> _decryptItem(ClipboardItem item) async {
    if (!item.encrypted) return item;
    if (!_cryptoService.hasKey) {
      return item.copyWith(
        content: item.contentType == 'image' ? '' : '[加密内容]',
        encrypted: true,
      );
    }

    try {
      final content = _cryptoService.decryptText(item.content);
      final preview = item.preview != null
          ? _cryptoService.decryptText(item.preview!)
          : null;
      return item.copyWith(
        content: content,
        preview: preview,
        encrypted: false,
      );
    } catch (_) {
      return item.copyWith(
        content: item.contentType == 'image' ? '' : '[解密失败]',
        encrypted: true,
      );
    }
  }

  /// 批量解密
  Future<List<ClipboardItem>> _decryptItems(List<ClipboardItem> items) async {
    final results = <ClipboardItem>[];
    for (final item in items) {
      results.add(await _decryptItem(item));
    }
    return results;
  }

  /// 释放资源
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _syncSubscription?.cancel();
    _syncService.dispose();
    _apiClient.dispose();
    _itemsController.close();
  }
}
