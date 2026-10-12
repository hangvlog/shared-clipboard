import 'package:clipboard_core/clipboard_core.dart';

/// 环境配置管理
///
/// 通过编译时变量区分环境：
/// flutter run --dart-define=ENV=development
/// flutter run --dart-define=ENV=production
class EnvConfig {
  static const String _env = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );

  static bool get isDevelopment => _env == 'development';
  static bool get isProduction => _env == 'production';

  /// API 基础 URL
  static String get apiBaseUrl {
    if (isProduction) {
      return const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://clawkit.chat/api',
      );
    }
    return 'http://10.0.2.2:6313'; // Android 模拟器访问宿主机
  }

  /// WebSocket 基础 URL
  static String get wsBaseUrl {
    if (isProduction) {
      return const String.fromEnvironment(
        'WS_BASE_URL',
        defaultValue: 'https://clawkit.chat',
      );
    }
    return 'http://10.0.2.2:6313';
  }

  static String get logEndpoint => const String.fromEnvironment(
    'CLIENT_LOG_URL',
    defaultValue: 'https://loghang.clawkit.chat/api/front/client-log/report',
  );

  /// 创建 SDK 配置
  static ClipboardConfig createConfig({String? token}) {
    return ClipboardConfig(
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsBaseUrl,
      token: token,
    );
  }
}
