/// 剪贴板条目数据模型
///
/// 对应后端 ClipboardItem 表结构，与 TypeScript 端的 ClipboardItem 接口保持一致。
class ClipboardItem {
  final String id;

  /// 文本内容、图片 base64 或 COS URL
  final String content;

  /// 内容类型：text / image / file / rich
  final String contentType;

  /// 来源设备 ID
  final String deviceId;

  /// 来源设备名称
  final String deviceName;

  /// 创建时间（ISO 8601）
  final String createdAt;

  /// 图片缩略图 base64
  final String? preview;

  /// COS 大图片 URL
  final String? imageUrl;

  /// 是否已加密
  final bool encrypted;

  ClipboardItem({
    required this.id,
    required this.content,
    required this.contentType,
    required this.deviceId,
    required this.deviceName,
    required this.createdAt,
    this.preview,
    this.imageUrl,
    this.encrypted = false,
  });

  /// 从后端 JSON 响应构造
  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String,
      content: json['content'] as String,
      contentType: json['contentType'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      createdAt: json['createdAt'] as String,
      preview: json['preview'] as String?,
      imageUrl: json['imageUrl'] as String?,
      encrypted: json['encrypted'] as bool? ?? false,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'contentType': contentType,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'createdAt': createdAt,
      'preview': preview,
      'imageUrl': imageUrl,
      'encrypted': encrypted,
    };
  }

  /// 创建一个修改了部分字段的副本
  ClipboardItem copyWith({
    String? id,
    String? content,
    String? contentType,
    String? deviceId,
    String? deviceName,
    String? createdAt,
    String? preview,
    String? imageUrl,
    bool? encrypted,
  }) {
    return ClipboardItem(
      id: id ?? this.id,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      createdAt: createdAt ?? this.createdAt,
      preview: preview ?? this.preview,
      imageUrl: imageUrl ?? this.imageUrl,
      encrypted: encrypted ?? this.encrypted,
    );
  }

  /// 用于本地 SQLite 存储的 Map
  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'content': content,
      'content_type': contentType,
      'device_id': deviceId,
      'device_name': deviceName,
      'created_at': createdAt,
      'preview': preview,
      'image_url': imageUrl,
      'encrypted': encrypted ? 1 : 0,
    };
  }

  /// 从 SQLite 行数据构造
  factory ClipboardItem.fromDbMap(Map<String, dynamic> map) {
    return ClipboardItem(
      id: map['id'] as String,
      content: map['content'] as String,
      contentType: map['content_type'] as String,
      deviceId: map['device_id'] as String,
      deviceName: map['device_name'] as String,
      createdAt: map['created_at'] as String,
      preview: map['preview'] as String?,
      imageUrl: map['image_url'] as String?,
      encrypted: (map['encrypted'] as int?) == 1,
    );
  }

  @override
  String toString() => 'ClipboardItem(id: $id, type: $contentType, device: $deviceName)';

  @override
  bool operator ==(Object other) => other is ClipboardItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
