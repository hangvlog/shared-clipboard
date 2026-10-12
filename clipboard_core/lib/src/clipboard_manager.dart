import 'dart:convert';
import 'dart:async';
import 'models/clipboard_item.dart';
import 'models/device_info.dart';
import 'api/clipboard_api_client.dart';
import 'sync/clipboard_sync_service.dart';
import 'crypto/clipboard_crypto_service.dart';
import 'crypto/clipboard_reader.dart';
import 'platform/platform_adapter.dart';
import 'config.dart';

class ClipboardManager {
  final ClipboardConfig config;
  final PlatformAdapter platform;
  final String? accountUsername;
  late final ClipboardReader _reader;
  String? encryptionNotice;
  final Future<void> Function(Future<void> Function())? clipboardWrite;
  final bool autoCopyRemote;
  bool _accountConfigLoaded = false;
  int _generation = 0;
  int _syncRequest = 0;
  bool _historyLoaded = false;
  bool _encryptedHistory = false;
  bool get hasEncryptionKey => _cryptoService.hasKey;
  bool _active(int generation) =>
      !_disposed && !_suspended && generation == _generation;

  late final ClipboardApiClient _apiClient;
  late final ClipboardSyncService _syncService;
  final ClipboardCryptoService _cryptoService = ClipboardCryptoService();

  List<ClipboardItem> _items = [];

  final _itemsController = StreamController<List<ClipboardItem>>.broadcast();
  Stream<List<ClipboardItem>> get itemsStream => _itemsController.stream;

  List<ClipboardItem> get items => List.unmodifiable(_items);

  Stream<SyncConnectionState> get connectionState =>
      _syncService.connectionState;

  bool get isConnected => _syncService.isConnected;

  late final DeviceInfo _deviceInfo;

  StreamSubscription? _syncSubscription;
  bool _suspended = false;
  bool _disposed = false;

  ClipboardManager({
    required this.config,
    required this.platform,
    this.accountUsername,
    this.clipboardWrite,
    this.autoCopyRemote = true,
  }) {
    _deviceInfo = DeviceInfo(
      deviceId: platform.getDeviceId(),
      deviceType: platform.getDeviceType(),
      deviceName: platform.getDeviceName(),
      platform: platform.getPlatformName(),
    );

    _apiClient = ClipboardApiClient(config: config);
    _reader = ClipboardReader(_apiClient, _cryptoService);
    _syncService = ClipboardSyncService(
      config: config,
      deviceInfo: _deviceInfo,
    );
  }

  Future<void> init() async {
    await restoreAccountEncryption();
    if (_disposed) return;
    await platform.initStorage();
    final localItems = await platform.getAllCachedItems();
    if (_disposed) return;
    if (localItems.isNotEmpty && !_suspended) {
      _items = localItems.map(ClipboardReader.diskMetadata).toList();
      if (!_disposed) _itemsController.add(_items);
    }

    _syncSubscription = _syncService.onClipboardSync.listen(_handleRemoteSync);

    await syncWithServer().catchError((Object _) {});

    if (!_suspended && !_disposed) _syncService.connect();
  }

  Future<void> restoreAccountEncryption() async {
    if (accountUsername != null && !_accountConfigLoaded) {
      try {
        final password = await _apiClient.getAccountEncryptionPassword();
        if (_disposed) return;
        if (password != null && password.isNotEmpty) {
          await _cryptoService.deriveKeyFromUsername(
            password,
            accountUsername!,
          );
        }
        if (_disposed) {
          _cryptoService.clearKey();
          return;
        }
        _accountConfigLoaded = true;
        encryptionNotice = null;
      } catch (_) {
        encryptionNotice = '账号加密配置读取失败，可刷新重试或输入原加密密码';
      }
    }
  }

  void _requireEncryptionReady() {
    if (accountUsername != null &&
        !_accountConfigLoaded &&
        !_cryptoService.hasKey) {
      throw StateError('账号加密配置尚未就绪，请刷新或输入原加密密码后同步');
    }
    if (accountUsername != null && !_historyLoaded) {
      throw StateError('请先刷新历史记录，再同步当前剪贴板');
    }
    if (!_cryptoService.hasKey && _encryptedHistory) {
      throw StateError('请先解锁加密剪贴板再同步');
    }
  }

  Future<void> _write(Future<void> Function() action) async {
    if (clipboardWrite != null) {
      await clipboardWrite!(action);
    } else {
      await action();
    }
  }

  void suspend() {
    _generation++;
    _suspended = true;
    _syncService.disconnect();
    _items = [];
    if (!_disposed) _itemsController.add(_items);
  }

  Future<void> resume() async {
    if (_disposed || !_suspended) return;
    _suspended = false;
    await restoreAccountEncryption();
    _syncService.connect();
    await syncWithServer();
  }

  Future<void> syncWithServer() async {
    if (_disposed || _suspended) return;
    final generation = _generation;
    final request = ++_syncRequest;
    bool active() => _active(generation) && request == _syncRequest;
    final beforeIds = _items.map((i) => i.id).toSet();
    final snapshot = await _apiClient.getHistory(limit: 50, metadataOnly: true);
    if (!active()) return;
    _encryptedHistory = snapshot.any((item) => item.encrypted);
    final decrypted = await _reader.history(snapshot, active: active);
    if (!active()) return;
    final additions = _items.where(
      (i) => !beforeIds.contains(i.id) && !decrypted.any((d) => d.id == i.id),
    );
    decrypted.insertAll(0, additions);
    await platform.replaceAllCached(
      snapshot.map(ClipboardReader.diskMetadata).toList(),
    );
    if (!active()) return;
    _historyLoaded = true;
    _items = decrypted;
    await platform.setLastSyncTime(DateTime.now().toUtc().toIso8601String());
    if (active()) _itemsController.add(_items);
  }

  Future<void> addTextItem(String content) async {
    if (_disposed || _suspended) return;
    _requireEncryptionReady();
    final generation = _generation;
    if (content.isEmpty) {
      throw StateError('内容为空');
    }
    if (utf8.encode(content).length > config.maxContentLength) {
      throw StateError('文本超过 100KB');
    }

    if (_items.isNotEmpty &&
        _items.first.contentType == 'text' &&
        _items.first.content == content &&
        !_items.first.metadataOnly) {
      return;
    }

    String sendContent = content;
    bool encrypted = false;
    String? contentHash;

    if (_cryptoService.hasKey) {
      sendContent = _cryptoService.encryptText(content);
      contentHash = ClipboardCryptoService.generateContentHash(content);
      encrypted = true;
    }

    final serverItem = await _apiClient.addItem(
      content: sendContent,
      contentType: 'text',
      deviceId: _deviceInfo.deviceId,
      deviceName: _deviceInfo.deviceName,
      encrypted: encrypted,
      contentHash: contentHash,
    );

    if (!_active(generation)) return;
    final localItem = serverItem.copyWith(content: content, encrypted: false);

    _items.insert(0, ClipboardReader.preview(localItem));
    if (_items.length > config.maxHistoryCount) {
      _items = _items.sublist(0, config.maxHistoryCount);
    }
    if (!_disposed) _itemsController.add(_items);

    await platform.upsertItems([ClipboardReader.diskMetadata(serverItem)]);

    _syncService.broadcastClipboardItem(serverItem);
  }

  Future<void> addImageItem(
    String imageContent, {
    String? preview,
    String? imageUrl,
    String contentType = 'image',
  }) async {
    if (_disposed || _suspended) return;
    _requireEncryptionReady();
    final generation = _generation;
    String sendContent = imageContent;
    String? sendPreview = preview;
    bool encrypted = false;
    String? contentHash;

    if (_cryptoService.hasKey) {
      sendContent = _cryptoService.encryptText(imageContent);
      if (preview != null) {
        sendPreview = _cryptoService.encryptText(preview);
      }
      contentHash = ClipboardCryptoService.generateContentHash(imageContent);
      encrypted = true;
    }
    final sendImageUrl = imageUrl != null && encrypted
        ? _cryptoService.encryptText(imageUrl)
        : imageUrl;

    final serverItem = await _apiClient.addItem(
      content: sendContent,
      contentType: contentType,
      deviceId: _deviceInfo.deviceId,
      deviceName: _deviceInfo.deviceName,
      preview: sendPreview,
      imageUrl: sendImageUrl,
      encrypted: encrypted,
      contentHash: contentHash,
    );

    if (!_active(generation)) return;
    final localItem = serverItem.copyWith(
      content: imageContent,
      preview: preview,
      imageUrl: imageUrl,
      encrypted: false,
    );

    _items.insert(0, ClipboardReader.preview(localItem));
    if (_items.length > config.maxHistoryCount) {
      _items = _items.sublist(0, config.maxHistoryCount);
    }
    if (!_disposed) _itemsController.add(_items);
    await platform.upsertItems([ClipboardReader.diskMetadata(serverItem)]);
    _syncService.broadcastClipboardItem(serverItem);
  }

  Future<void> deleteItem(String id) async {
    if (_disposed) return;
    await _apiClient.deleteItem(id);
    if (_disposed) return;
    _items.removeWhere((item) => item.id == id);
    if (!_disposed) _itemsController.add(_items);
    await platform.deleteCachedItem(id);
  }

  Future<void> clearHistory() async {
    if (_disposed) return;
    await _apiClient.clearHistory();
    if (_disposed) return;
    _items.clear();
    if (!_disposed) _itemsController.add(_items);
    await platform.clearAllCached();
  }

  Future<ClipboardItem> readItem(ClipboardItem item) async {
    if (_disposed || _suspended) throw StateError('请在应用前台查看');
    final generation = _generation;
    final result = await _reader.read(item);
    if (!_active(generation)) throw StateError('查看已取消');
    if (result.encrypted) throw StateError(result.content);
    return result;
  }

  Future<void> copyToClipboard(ClipboardItem item) async {
    item = await readItem(item);
    await _write(() async {
      if (item.contentType == 'rich' &&
          item.imageUrl?.startsWith('data:image/') == true) {
        await platform.writeClipboardRich(
          item.content,
          base64Decode(item.imageUrl!.split(',').last),
        );
      } else if (item.contentType == 'text' || item.contentType == 'rich') {
        await platform.writeClipboardText(item.content);
      } else if (item.contentType == 'image') {
        if (!item.content.startsWith('data:image/')) {
          throw StateError('旧版图片链接请在原设备打开');
        }
        await platform.writeClipboardImage(
          base64Decode(item.content.split(',').last),
        );
      }
    });
  }

  Future<void> setEncryptionKey(String password, String username) async {
    await _cryptoService.deriveKeyFromUsername(password, username);
    if (_disposed) {
      _cryptoService.clearKey();
      return;
    }
    _accountConfigLoaded = true;
    encryptionNotice = null;
    await syncWithServer();
  }

  void clearEncryptionKey() {
    _cryptoService.clearKey();
  }

  Future<void> _handleRemoteSync(ClipboardItem rawItem) async {
    if (_items.any((i) => i.id == rawItem.id)) return;

    if (_disposed || _suspended) return;
    final item = _reader.decrypt(rawItem);
    if (_disposed || _suspended) return;

    _items.insert(0, ClipboardReader.preview(item));
    if (_items.length > config.maxHistoryCount) {
      _items = _items.sublist(0, config.maxHistoryCount);
    }
    if (!_disposed) _itemsController.add(_items);
    await platform.upsertItems([ClipboardReader.diskMetadata(rawItem)]);

    if (autoCopyRemote &&
        item.deviceId != _deviceInfo.deviceId &&
        item.contentType == 'text' &&
        !item.encrypted &&
        !_disposed &&
        !_suspended) {
      await _write(() => platform.writeClipboardText(item.content));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _items = [];
    _cryptoService.clearKey();
    _syncSubscription?.cancel();
    _syncService.dispose();
    _apiClient.dispose();
    _itemsController.close();
  }
}
