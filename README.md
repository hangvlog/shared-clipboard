# 共享剪贴板 (Shared Clipboard)

跨平台剪贴板同步解决方案，支持多设备间实时同步文本、图片等内容。

## 项目结构

```
.
├── clipboard_core/          # Dart SDK - 跨平台核心逻辑
│   ├── lib/                 # SDK 源码
│   ├── pubspec.yaml         # Dart 依赖
│   └── README.md            # SDK 文档
├── clipboard_app/           # Flutter 移动端应用
│   ├── lib/                 # Flutter 源码
│   ├── android/             # Android 配置
│   ├── ios/                 # iOS 配置
│   ├── pubspec.yaml         # Flutter 依赖
│   └── README.md            # App 文档
└── backend/                 # 后端 API
    ├── clipboard.py         # REST API
    └── ws.py                # WebSocket 事件
```

## 功能特性

- **实时同步** - WebSocket 即时同步，一处复制，处处可用
- **端到端加密** - AES-256-GCM 加密，确保数据安全
- **多设备支持** - 桌面端、移动端（iOS/Android）同时使用
- **历史记录** - 自动保存最近 200 条剪贴板记录
- **增量同步** - 智能增量同步，节省流量

## 平台兼容性

| 平台 | 支持状态 | 同步方式 |
|------|---------|---------|
| macOS | ✅ 完整 | 自动监听 |
| Windows | ✅ 完整 | 自动监听 |
| iOS | ✅ 支持 | 手动同步 |
| Android | ✅ 支持 | 手动同步 |

> **注意**: 移动端因系统限制无法实现后台自动监听，需用户点击"同步"按钮。

## 快速开始

### 后端部署

```bash
cd backend
pip install -r requirements.txt
python clipboard.py
```

### 移动端开发

```bash
cd clipboard_app
flutter pub get
flutter run
```

### SDK 使用

```dart
import 'package:clipboard_core/clipboard_core.dart';

final manager = ClipboardManager(
  config: ClipboardConfig(
    apiBaseUrl: 'http://your-server:6313',
    wsBaseUrl: 'ws://your-server:6313',
    token: 'your-jwt-token',
  ),
  platform: YourPlatformAdapter(),
);

await manager.init();
await manager.addTextItem('Hello World');
```

## 许可证

MIT License
