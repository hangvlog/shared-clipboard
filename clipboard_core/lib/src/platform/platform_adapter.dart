import 'dart:typed_data';
import '../models/clipboard_item.dart';

/// 剪贴板内容（平台原生读取结果）
class ClipboardContent {
  /// 内容类型：text / image / rich
  final String contentType;

  /// 文本内容
  final String? text;

  /// 图片原始字节数据
  final Uint8List? imageBytes;

  /// 内容哈希（用于变化检测）
  final String hash;

  ClipboardContent({
    required this.contentType,
    this.text,
    this.imageBytes,
    required this.hash,
  });
}

/// 平台适配器抽象接口
///
/// 各平台（Flutter 移动端、Tauri 桌面端、Web 浏览器端）需实现此接口。
/// SDK 核心逻辑通过此接口调用平台特有能力，实现依赖反转。
abstract class PlatformAdapter {
  // ============================================
  // 剪贴板操作
  // ============================================

  /// 读取系统剪贴板内容
  Future<ClipboardContent?> readClipboard();

  /// 将文本写入系统剪贴板
  Future<void> writeClipboardText(String text);

  /// 将图片写入系统剪贴板
  Future<void> writeClipboardImage(Uint8List imageBytes);

  Future<void> writeClipboardRich(String text, Uint8List imageBytes) =>
      throw UnsupportedError("当前平台尚不支持图文一起复制");

  // ============================================
  // 本地持久化存储
  // ============================================

  /// 初始化本地存储
  Future<void> initStorage();

  /// 获取所有缓存的剪贴板条目
  Future<List<ClipboardItem>> getAllCachedItems();

  /// 获取缓存条目数量
  Future<int> getCachedCount();

  /// 获取最后同步时间
  Future<String?> getLastSyncTime();

  /// 设置最后同步时间
  Future<void> setLastSyncTime(String time);

  /// 插入或更新条目
  Future<void> upsertItems(List<ClipboardItem> items);

  /// 删除单条缓存
  Future<void> deleteCachedItem(String id);

  /// 清空全部缓存
  Future<void> clearAllCached();

  /// 全量替换缓存
  Future<void> replaceAllCached(List<ClipboardItem> items);

  // ============================================
  // 设备信息
  // ============================================

  /// 获取或生成设备唯一 ID（持久化存储）
  String getDeviceId();

  /// 获取设备名称
  String getDeviceName();

  /// 获取设备类型（desktop / mobile / web）
  String getDeviceType();

  /// 获取操作系统平台标识
  String getPlatformName();

  // ============================================
  // 图片处理
  // ============================================

  /// 生成图片缩略图（返回 base64 JPEG）
  Future<String> generateThumbnail(Uint8List imageBytes, {int maxSize = 200});

  /// 图片字节数据转 base64 data URI
  String imageBytesToBase64(Uint8List imageBytes);
}
