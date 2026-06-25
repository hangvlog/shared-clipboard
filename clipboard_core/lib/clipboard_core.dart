/// 跨平台共享剪贴板 SDK
///
/// 提供平台无关的核心逻辑，包括：
/// - [ClipboardApiClient] HTTP API 客户端
/// - [ClipboardSyncService] Socket.IO 实时同步
/// - [ClipboardCryptoService] AES-256-GCM 端到端加密
/// - [ClipboardItem] 统一数据模型
/// - [PlatformAdapter] 平台适配抽象接口
library clipboard_core;

export 'src/models/clipboard_item.dart';
export 'src/models/device_info.dart';
export 'src/api/clipboard_api_client.dart';
export 'src/sync/clipboard_sync_service.dart';
export 'src/crypto/clipboard_crypto_service.dart';
export 'src/platform/platform_adapter.dart';
export 'src/clipboard_manager.dart';
export 'src/config.dart';
