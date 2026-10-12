import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:clipboard_core/clipboard_core.dart';

/// 单条剪贴板记录的列表项组件
class ClipboardItemTile extends StatelessWidget {
  final ClipboardItem item;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;
  final VoidCallback? onView;

  const ClipboardItemTile({
    super.key,
    required this.item,
    required this.onCopy,
    required this.onDelete,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onView ?? onCopy,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 内容区域
              _buildContent(context),
              const SizedBox(height: 8),
              // 底部信息栏
              Row(
                children: [
                  // 设备图标
                  Icon(_getDeviceIcon(), size: 14, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      item.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 时间
                  Icon(Icons.access_time, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatTime(item.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  // 类型标签
                  _buildTypeBadge(context),
                  const SizedBox(width: 8),
                  if (onView != null)
                    IconButton(
                      tooltip: '查看完整内容',
                      onPressed: onView,
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                    ),
                  IconButton(
                    tooltip: '复制',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  // 删除按钮
                  if (onDelete != null)
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (item.encrypted) {
      return Text(item.content.isEmpty ? '加密记录 · 请解锁后查看' : item.content);
    }
    if (item.metadataOnly && item.contentType == 'image') {
      return const Text('图片 · 点按查看');
    }
    switch (item.contentType) {
      case 'image':
        return _buildImageContent(context);
      case 'rich':
        return _buildRichContent(context);
      default:
        return _buildTextContent(context);
    }
  }

  Widget _buildTextContent(BuildContext context) {
    return Text(
      item.content,
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final imageData = item.preview ?? item.content;
    if (imageData.startsWith('data:image')) {
      try {
        final base64Str = imageData.split(',').last;
        final bytes = base64Decode(base64Str);
        return ClipRect(
          child: SizedBox(
            height: 120,
            width: double.infinity,
            child: Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 400),
          ),
        );
      } catch (_) {}
    }

    // URL 图片
    if (imageData.startsWith('http')) {
      return SizedBox(
        height: 120,
        width: double.infinity,
        child: Image.network(
          imageData,
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, _, _) => _buildImagePlaceholder(context),
        ),
      );
    }

    return _buildImagePlaceholder(context);
  }

  Widget _buildRichContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 文本部分
        Text(
          item.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // 图片部分（如有预览）
        if (item.imageUrl != null || item.preview != null) ...[
          const SizedBox(height: 8),
          SizedBox(height: 80, child: _buildThumbnail(context)),
        ],
      ],
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final source = item.preview ?? item.imageUrl ?? '';
    if (source.startsWith('data:image')) {
      try {
        final bytes = base64Decode(source.split(',').last);
        return Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 400);
      } catch (_) {}
    }
    if (source.startsWith('http')) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, _, _) => _buildImagePlaceholder(context),
      );
    }
    return _buildImagePlaceholder(context);
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildTypeBadge(BuildContext context) {
    final label = switch (item.contentType) {
      'image' => '图片',
      'rich' => '图文',
      'file' => '文件',
      _ => '文本',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  IconData _getDeviceIcon() {
    if (item.deviceName.toLowerCase().contains('ipad')) return Icons.tablet_mac;
    if (item.deviceName.toLowerCase().contains('iphone') ||
        item.deviceName.toLowerCase().contains('android') ||
        item.deviceName.toLowerCase().contains('mobile')) {
      return Icons.phone_android;
    }
    if (item.deviceName.toLowerCase().contains('browser') ||
        item.deviceName.toLowerCase().contains('web')) {
      return Icons.language;
    }
    return Icons.computer;
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
      if (diff.inDays < 1) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';

      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}
