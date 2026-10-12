/// SDK 配置
class ClipboardConfig {
  /// 后端 API 基础 URL（如 http://localhost:6313）
  final String apiBaseUrl;

  /// WebSocket 服务地址（如 ws://localhost:6313）
  final String wsBaseUrl;

  /// JWT Token（登录后设置）
  String? token;

  /// 是否启用端到端加密
  final bool encryptionEnabled;

  /// 最大历史记录数
  final int maxHistoryCount;

  /// 内容最大长度（字节）
  final int maxContentLength;

  /// 图片大小阈值（超过此值上传到 COS，否则用 base64）
  final int imageSizeThreshold;

  ClipboardConfig({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    this.token,
    this.encryptionEnabled = false,
    this.maxHistoryCount = 200,
    this.maxContentLength = 100000,
    this.imageSizeThreshold = 500 * 1024,
  });

  /// 开发环境默认配置
  factory ClipboardConfig.development() {
    return ClipboardConfig(
      apiBaseUrl: 'http://localhost:6313',
      wsBaseUrl: 'http://localhost:6313',
    );
  }

  /// 生产环境默认配置
  factory ClipboardConfig.production() {
    return ClipboardConfig(
      apiBaseUrl: 'https://clawkit.chat/api',
      wsBaseUrl: 'https://clawkit.chat',
    );
  }
}
