import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:clipboard_core/clipboard_core.dart';
import '../services/env_config.dart';
import '../services/flutter_platform_adapter.dart';
import 'auth_store.dart';
import '../services/foreground_clipboard_sync.dart';
import '../services/android_clipboard_events.dart';
import '../services/mobile_diagnostics.dart';

/// 剪贴板状态管理（Provider）
///
/// 连接 clipboard_core SDK 的 ClipboardManager 与 Flutter UI 层。
class ClipboardStore extends ChangeNotifier with WidgetsBindingObserver {
  ClipboardStore() {
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) _androidEvents.start(() => _autoSync?.changed());
  }
  final _diagnostics = MobileDiagnostics(
    endpoint: EnvConfig.isProduction ? EnvConfig.logEndpoint : '',
  );
  final _androidEvents = AndroidClipboardEvents();
  ForegroundClipboardSync? _autoSync;
  String? syncNotice;
  bool get needsUnlock => _items.any(
    (item) =>
        item.encrypted &&
        (!(_manager?.hasEncryptionKey ?? false) ||
            item.content.contains('其他加密密码')),
  );
  String? get encryptionNotice => _manager?.encryptionNotice;
  String? _token;
  int _generation = 0;
  bool _disposed = false;
  bool get _background =>
      WidgetsBinding.instance.lifecycleState != null &&
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _diagnostics.pause();
      _autoSync?.pause();
      _manager?.suspend();
      PaintingBinding.instance.imageCache.clear();
    } else if (state == AppLifecycleState.resumed) {
      _diagnostics.resume();
      final generation = _generation;
      _manager
          ?.resume()
          .then((_) {
            if (Platform.isAndroid &&
                !_background &&
                !_disposed &&
                generation == _generation) {
              _autoSync?.enabled = true;
              _autoSync?.changed();
            }
          })
          .catchError((Object _) {
            if (_disposed || generation != _generation) return;
            syncNotice = '恢复同步失败，请点按刷新';
            if (!_disposed) notifyListeners();
          });
    }
  }

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
    if (_token == authStore.token) return;
    _cleanup();
    _token = authStore.token;
    if (_token != null && authStore.username != null) {
      _initialize(_token!, authStore.username!);
    }
  }

  Future<void> _initialize(String token, String username) async {
    final generation = _generation;
    final platform = FlutterPlatformAdapter(accountId: username);
    _platform = platform;
    _isLoading = true;
    ClipboardManager? manager;
    try {
      await platform.initStorage();
      await platform.loadDeviceName();
      if (_disposed || generation != _generation) {
        await platform.close();
        return;
      }
      manager = ClipboardManager(
        config: EnvConfig.createConfig(token: token),
        platform: platform,
        accountUsername: username,
        autoCopyRemote: false,
        clipboardWrite: (write) async {
          if (_autoSync != null) {
            await _autoSync!.suppressDuring(write);
          } else {
            await write();
          }
        },
      );
      _manager = manager;
      if (Platform.isAndroid) {
        _autoSync = ForegroundClipboardSync(
          read: platform.readClipboard,
          send: (content) => _sendContent(content, generation),
          status: (message) {
            if (_disposed || generation != _generation) return;
            unawaited(
              _diagnostics.report(
                message == '剪贴板已自动同步'
                    ? MobileEvent.autoSynced
                    : MobileEvent.autoSyncFailed,
              ),
            );
            syncNotice = message;
            notifyListeners();
          },
        );
      }
      if (_background) manager.suspend();
      _itemsSub = manager.itemsStream.listen((items) {
        if (_disposed || generation != _generation) return;
        _items = items;
        notifyListeners();
      });
      _connectionSub = manager.connectionState.listen((state) {
        if (_disposed || generation != _generation) return;
        _isConnected = state == SyncConnectionState.connected;
        notifyListeners();
      });
      await manager.init();
      if (_disposed || generation != _generation) {
        manager.dispose();
        await platform.close();
        return;
      }
      unawaited(
        _diagnostics.report(
          manager.encryptionNotice == null
              ? MobileEvent.initialized
              : MobileEvent.accountConfigUnavailable,
        ),
      );
      _isInitialized = true;
      _autoSync?.enabled = !_background;
      _autoSync?.changed();
    } catch (e) {
      manager?.dispose();
      if (!_disposed && generation == _generation) {
        unawaited(_diagnostics.report(MobileEvent.initializationFailed));
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 手动同步剪贴板（用户主动触发）
  ///
  /// 移动端由于系统限制，不能像桌面端那样静默监控，
  /// 提供手动"粘贴并同步"的入口。
  /// 支持文本、图片、图文混合内容。
  Future<void> syncCurrentClipboard() async {
    if (_manager == null || _platform == null) throw StateError('尚未登录或初始化未完成');

    try {
      final generation = _generation;
      if (_background) throw StateError('请在应用前台同步');
      final content = await _platform!.readClipboard();
      if (generation != _generation || _disposed) return;
      if (content == null) throw StateError('剪贴板为空或不支持该格式');

      await _sendContent(content, generation);
      await _autoSync?.suppressCurrent();
    } catch (e) {
      debugPrint('[ClipboardStore] 同步剪贴板失败');
      rethrow;
    }
  }

  Future<void> _sendContent(ClipboardContent content, int generation) async {
    if (_disposed || _background || generation != _generation) {
      throw StateError('同步已取消，请返回应用重试');
    }
    switch (content.contentType) {
      case 'text':
        if (content.text?.isNotEmpty == true) {
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
        } else if (content.text?.isNotEmpty == true) {
          await _manager!.addTextItem(content.text!);
        }
        break;
    }
  }

  Future<ClipboardItem> readItem(ClipboardItem item) async {
    if (_manager == null) throw StateError('尚未登录');
    try {
      return await _manager!.readItem(item);
    } catch (_) {
      unawaited(_diagnostics.report(MobileEvent.readFailed));
      rethrow;
    }
  }

  /// 添加图片条目
  Future<void> _addImageItem(Uint8List imageBytes) async {
    try {
      // 转为 base64
      final base64Content = _platform!.imageBytesToBase64(imageBytes);

      await _manager!.addImageItem(base64Content);
    } catch (e) {
      debugPrint('[ClipboardStore] 添加图片失败: $e');
      rethrow;
    }
  }

  /// 添加图文混合条目
  Future<void> _addRichItem(String text, Uint8List imageBytes) async {
    try {
      // 转为 base64
      final base64Content = _platform!.imageBytesToBase64(imageBytes);

      await _manager!.addImageItem(
        text,
        imageUrl: base64Content,
        contentType: 'rich',
      );
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
      await _manager?.restoreAccountEncryption();
      await _manager?.syncWithServer();
    } catch (e) {
      unawaited(_diagnostics.report(MobileEvent.historyFailed));
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
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

  Future<void> unlock(String password, String username) async {
    await _manager?.setEncryptionKey(password, username);
  }

  void _cleanup() {
    _generation++;
    _autoSync?.dispose();
    _autoSync = null;
    syncNotice = null;
    _itemsSub?.cancel();
    _connectionSub?.cancel();
    _manager?.dispose();
    _manager = null;
    if (_isInitialized) {
      _platform?.close();
    }
    _platform = null;
    _isLoading = false;
    _items = [];
    _isConnected = false;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _diagnostics.dispose();
    _androidEvents.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _cleanup();
    super.dispose();
  }
}
