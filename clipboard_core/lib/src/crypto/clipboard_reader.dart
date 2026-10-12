import '../api/clipboard_api_client.dart';
import '../models/clipboard_item.dart';
import 'clipboard_crypto_service.dart';

/// Full bodies exist only while reading/copying; list state keeps short previews.
class ClipboardReader {
  final ClipboardApiClient api;
  final ClipboardCryptoService crypto;
  ClipboardReader(this.api, this.crypto);

  ClipboardItem decrypt(ClipboardItem item) {
    if (item.metadataOnly)
      return preview(
        item.copyWith(
          content: crypto.hasKey ? '加密记录 · 点按查看' : '加密记录 · 需要原密码解锁',
        ),
      );
    if (!item.encrypted) return item;
    if (!crypto.hasKey) return item.copyWith(content: '需要原加密密码解锁');
    try {
      final image = item.imageUrl;
      return item.copyWith(
        content: crypto.decryptText(item.content),
        preview: item.preview == null
            ? null
            : crypto.decryptText(item.preview!),
        imageUrl:
            image != null &&
                !image.startsWith('data:') &&
                !image.startsWith('https://')
            ? crypto.decryptText(image)
            : image,
        encrypted: false,
      );
    } catch (_) {
      return item.copyWith(content: '此记录使用了其他加密密码');
    }
  }

  Future<ClipboardItem> read(ClipboardItem item) async =>
      decrypt(item.metadataOnly ? await api.getItem(item.id) : item);

  Future<List<ClipboardItem>> history(
    List<ClipboardItem> snapshot, {
    required bool Function() active,
  }) async {
    final visible = <ClipboardItem>[];
    for (final item in snapshot) {
      if (!active()) break;
      // One bounded text body at a time. Never preload full image histories.
      if (item.encrypted && item.contentType == 'text' && crypto.hasKey) {
        try {
          final full = await read(item);
          if (!active()) break;
          visible.add(preview(full));
          continue;
        } catch (_) {
          visible.add(item.copyWith(content: '暂时无法读取，点按重试'));
          continue;
        }
      }
      visible.add(
        item.encrypted
            ? preview(
                item.copyWith(
                  content: crypto.hasKey ? '加密记录 · 点按查看' : '加密记录 · 需要原密码解锁',
                ),
              )
            : preview(item),
      );
    }
    return visible;
  }

  static ClipboardItem preview(ClipboardItem item) => ClipboardItem(
    id: item.id,
    content: item.contentType == 'image'
        ? ''
        : String.fromCharCodes(item.content.runes.take(240)),
    contentType: item.contentType,
    deviceId: item.deviceId,
    deviceName: item.deviceName,
    createdAt: item.createdAt,
    encrypted: item.encrypted,
    metadataOnly: true,
  );

  static ClipboardItem diskMetadata(ClipboardItem item) =>
      preview(item.encrypted ? item.copyWith(content: '加密记录 · 需要原密码解锁') : item);
}
