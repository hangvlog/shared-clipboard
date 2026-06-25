import 'package:clipboard_core/clipboard_core.dart';

/// 环境配置管理
///
/// 通过编译时变量区分环境：
/// flutter run --dart-define=ENV=development
/// flutter run --dart-define=ENV=production
class EnvConfig {
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'development');

  static bool get isDevelopment => _env == 'development';
  static bool get isProduction => _env == 'production';

  /// API 基础 URL
  static String get apiBaseUrl {
    if (isProduction) return 'http://62.234.124.12:6313';
    return 'http://10.0.2.2:6313'; // Android 模拟器访问宿主机
  }

  /// WebSocket 基础 URL
  static String get wsBaseUrl {
    if (isProduction) return 'http://62.234.124.12:6313';
    return 'http://10.0.2.2:6313';
  }

  /// 创建 SDK 配置
  static ClipboardConfig createConfig({String? token}) {
    return ClipboardConfig(
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsBaseUrl,
      token: token,
    );
  }
}
