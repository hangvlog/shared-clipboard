import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:clipboard_core/clipboard_core.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart' as hash_lib;

/// Flutter 移动端平台适配器实现
///
/// 实现 PlatformAdapter 接口，为 iOS/Android 提供：
/// - 系统剪贴板读写（super_clipboard）
/// - SQLite 本地缓存（sqflite）
/// - 设备信息获取（device_info_plus）
/// - 图片缩略图生成（image 库）
class FlutterPlatformAdapter implements PlatformAdapter {
  FlutterPlatformAdapter({required this.accountId});
  final String accountId;
  Database? _db;
  SharedPreferences? _prefs;
  String? _deviceId;
  String? _deviceName;

  String get _dbName =>
      'clipboard_cache_${hash_lib.sha256.convert(utf8.encode(accountId))}.db';
  static const _prefsDeviceIdKey = 'clipboard_device_id';
  String get _prefsSyncTimeKey => 'clipboard_last_sync_time:$accountId';

  // ============================================
  // 剪贴板操作
  // ============================================

  @override
  Future<ClipboardContent?> readClipboard() async {
    try {
      final reader = await SystemClipboard.instance?.read();
      if (reader == null) return null;

      // 先尝试读取图片（优先级更高，因为图文混合时通常包含文本+图片）
      for (final item in reader.items) {
        for (final format in [Formats.png, Formats.jpeg]) {
          if (!item.canProvide(format)) continue;
          final loaded = Completer<Uint8List?>();
          final progress = item.getFile(format, (file) async {
            try {
              loaded.complete(await file.readAll());
            } catch (error) {
              loaded.completeError(error);
            }
          }, onError: loaded.completeError);
          if (progress == null) continue;
          final imageData = await loaded.future;
          if (imageData == null || imageData.isEmpty) continue;
          final text = item.canProvide(Formats.plainText)
              ? await item.readValue(Formats.plainText)
              : null;
          return ClipboardContent(
            contentType: text != null && text.isNotEmpty ? 'rich' : 'image',
            text: text,
            imageBytes: imageData,
            hash: _quickHashBytes(imageData),
          );
        }
      }

      // 纯文本
      for (final item in reader.items) {
        if (item.canProvide(Formats.plainText)) {
          final text = await item.readValue(Formats.plainText);
          if (text != null && text.isNotEmpty) {
            final hash = _quickHash(text);
            return ClipboardContent(
              contentType: 'text',
              text: text,
              hash: hash,
            );
          }
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeClipboardText(String text) async {
    try {
      final item = DataWriterItem();
      item.add(Formats.plainText(text));
      await SystemClipboard.instance?.write([item]);
    } catch (_) {
      // 静默处理（移动端可能因权限限制失败）
    }
  }

  @override
  Future<void> writeClipboardImage(Uint8List imageBytes) async {
    // 移动端图片写入剪贴板限制较多，暂不实现
  }

  // ============================================
  // 本地持久化存储（SQLite）
  // ============================================

  @override
  Future<void> initStorage() async {
    if (_db != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = path_lib.join(dir.path, _dbName);

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS clipboard_cache (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            content_type TEXT NOT NULL,
            device_id TEXT NOT NULL,
            device_name TEXT DEFAULT '',
            created_at TEXT NOT NULL,
            preview TEXT,
            image_url TEXT,
            encrypted INTEGER DEFAULT 0
          )
        ''');
      },
    );

    _prefs = await SharedPreferences.getInstance();
  }

  @override
  Future<List<ClipboardItem>> getAllCachedItems() async {
    final rows = await _db!.query(
      'clipboard_cache',
      orderBy: 'created_at DESC',
      limit: 200,
    );
    return rows.map((r) => ClipboardItem.fromDbMap(r)).toList();
  }

  @override
  Future<int> getCachedCount() async {
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM clipboard_cache',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<String?> getLastSyncTime() async {
    return _prefs?.getString(_prefsSyncTimeKey);
  }

  @override
  Future<void> setLastSyncTime(String time) async {
    await _prefs?.setString(_prefsSyncTimeKey, time);
  }

  @override
  Future<void> upsertItems(List<ClipboardItem> items) async {
    final batch = _db!.batch();
    for (final item in items) {
      batch.insert(
        'clipboard_cache',
        item.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    batch.rawDelete(
      'DELETE FROM clipboard_cache WHERE id NOT IN '
      '(SELECT id FROM clipboard_cache ORDER BY created_at DESC, id DESC LIMIT 200)',
    );
    await batch.commit(noResult: true);
  }

  @override
  Future<void> deleteCachedItem(String id) async {
    await _db!.delete('clipboard_cache', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearAllCached() async {
    await _db!.delete('clipboard_cache');
    await _prefs?.remove(_prefsSyncTimeKey);
  }

  @override
  Future<void> replaceAllCached(List<ClipboardItem> items) async {
    await _db!.delete('clipboard_cache');
    await upsertItems(items);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ============================================
  // 设备信息
  // ============================================

  @override
  String getDeviceId() {
    if (_deviceId != null) return _deviceId!;

    _deviceId = _prefs?.getString(_prefsDeviceIdKey);
    if (_deviceId == null) {
      _deviceId =
          'mobile-${DateTime.now().millisecondsSinceEpoch}-'
          '${DateTime.now().microsecond.toRadixString(36)}';
      _prefs?.setString(_prefsDeviceIdKey, _deviceId!);
    }
    return _deviceId!;
  }

  @override
  String getDeviceName() {
    if (_deviceName != null) return _deviceName!;
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android';
    return 'Mobile';
  }

  @override
  String getDeviceType() => 'mobile';

  @override
  String getPlatformName() {
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    return Platform.operatingSystem;
  }

  /// 异步加载详细设备名称
  Future<void> loadDeviceName() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfoPlugin.androidInfo;
      _deviceName = '${info.brand} ${info.model}';
    } else if (Platform.isIOS) {
      final info = await deviceInfoPlugin.iosInfo;
      _deviceName = info.utsname.machine;
    }
  }

  // ============================================
  // 图片处理
  // ============================================

  @override
  Future<String> generateThumbnail(
    Uint8List imageBytes, {
    int maxSize = 200,
  }) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图片');

    img.Image resized;
    if (image.width > image.height) {
      resized = img.copyResize(image, width: maxSize);
    } else {
      resized = img.copyResize(image, height: maxSize);
    }

    final jpegBytes = img.encodeJpg(resized, quality: 70);
    return 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
  }

  @override
  String imageBytesToBase64(Uint8List imageBytes) {
    return 'data:image/png;base64,${base64Encode(imageBytes)}';
  }

  // ============================================
  // 内部工具
  // ============================================

  String _quickHash(String text) {
    final bytes = utf8.encode(text);
    final digest = hash_lib.sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  String _quickHashBytes(Uint8List bytes) {
    final digest = hash_lib.sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
}
