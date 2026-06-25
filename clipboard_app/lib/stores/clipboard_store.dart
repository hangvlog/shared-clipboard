import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:clipboard_core/clipboard_core.dart';
import '../services/env_config.dart';
import '../services/flutter_platform_adapter.dart';
import 'auth_store.dart';

/// 剪贴板状态管理（Provider）
///
/// 连接 clipboard_core SDK 的 ClipboardManager 与 Flutter UI 层。
class ClipboardStore extends ChangeNotifier {
  ClipboardManager? _manager;
  FlutterPlatformAdapter? _platform;

  List<ClipboardItem> _items = [];
  bool _isLoading = false;
  bool _isConnected = false;
  bool _isInitialized = false;

  StreamSubscription? _itemsSub;
  StreamSubscription? _connectionSub;

  List<ClipboardItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  /// 当 AuthStore 变化时调用
  void updateAuth(AuthStore authStore) {
    if (authStore.isLoggedIn && !_isInitialized) {
      _initialize(authStore.token!, authStore.username!, authStore.nickname);
    } else if (!authStore.isLoggedIn && _isInitialized) {
      _cleanup();
    }
  }

  /// 初始化 SDK
  Future<void> _initialize(String token, String username, String? nickname) async {
    _isLoading = true;
    notifyListeners();

    try {
      _platform = FlutterPlatformAdapter();

      final config = EnvConfig.createConfig(token: token);
      await _platform!.initStorage();
      await _platform!.loadDeviceName();

      _manager = ClipboardManager(
        config: config,
        platform: _platform!,
      );

      // 监听条目变化
      _itemsSub = _manager!.itemsStream.listen((items) {
        _items = items;
        notifyListeners();
      });

      // 监听连接状态
      _connectionSub = _manager!.connectionState.listen((state) {
        _isConnected = state == SyncConnectionState.connected;
        notifyListeners();
      });

      await _manager!.init();

      _isInitialized = true;
    } catch (e) {
      debugPrint('[ClipboardStore] 初始化失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 手动同步剪贴板（用户主动触发）
  ///
  /// 移动端由于系统限制，不能像桌面端那样静默监控，
  /// 提供手动"粘贴并同步"的入口。
  /// 支持文本、图片、图文混合内容。
  Future<void> syncCurrentClipboard() async {
    if (_manager == null || _platform == null) return;

    try {
      final content = await _platform!.readClipboard();
      if (content == null) return;

      switch (content.contentType) {
        case 'text':
          if (content.text != null && content.text!.isNotEmpty) {
            await _manager!.addTextItem(content.text!);
          }
          break;
        case 'image':
          if (content.imageBytes != null) {
            await _addImageItem(content.imageBytes!);
          }
          break;
        case 'rich':
          if (content.imageBytes != null) {
            await _addRichItem(content.text ?? '', content.imageBytes!);
          } else if (content.text != null) {
            await _manager!.addTextItem(content.text!);
          }
          break;
      }
    } catch (e) {
      debugPrint('[ClipboardStore] 同步剪贴板失败: $e');
    }
  }

  /// 添加图片条目
  Future<void> _addImageItem(Uint8List imageBytes) async {
    try {
      // 生成缩略图
      final preview = await _platform!.generateThumbnail(imageBytes, maxSize: 200);
      // 转为 base64
      final base64Content = _platform!.imageBytesToBase64(imageBytes);

      await _manager!.addImageItem(
        base64Content,
        preview: preview,
      );
    } catch (e) {
      debugPrint('[ClipboardStore] 添加图片失败: $e');
      rethrow;
    }
  }

  /// 添加图文混合条目
  Future<void> _addRichItem(String text, Uint8List imageBytes) async {
    try {
      // 生成缩略图
      final preview = await _platform!.generateThumbnail(imageBytes, maxSize: 200);
      // 转为 base64
      final base64Content = _platform!.imageBytesToBase64(imageBytes);

      await _manager!.addImageItem(
        base64Content,
        preview: preview,
      );
      // TODO: 后端 API 需要支持真正的图文混合类型
      // 目前先作为图片上传，文本内容在 UI 层展示
    } catch (e) {
      debugPrint('[ClipboardStore] 添加图文内容失败: $e');
      rethrow;
    }
  }

  /// 刷新（重新从服务端同步）
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _manager?.syncWithServer();
    } catch (e) {
      debugPrint('[ClipboardStore] 刷新失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 手动添加文本
  Future<void> addText(String text) async {
    await _manager?.addTextItem(text);
  }

  /// 复制到剪贴板
  Future<void> copyItem(ClipboardItem item) async {
    await _manager?.copyToClipboard(item);
  }

  /// 删除条目
  Future<void> deleteItem(String id) async {
    await _manager?.deleteItem(id);
  }

  /// 清空历史
  Future<void> clearHistory() async {
    await _manager?.clearHistory();
  }

  void _cleanup() {
    _itemsSub?.cancel();
    _connectionSub?.cancel();
    _manager?.dispose();
    _manager = null;
    _platform = null;
    _items = [];
    _isConnected = false;
    _isInitialized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
