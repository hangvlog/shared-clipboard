# 共享剪贴板 (Shared Clipboard)

跨平台剪贴板同步解决方案，支持多设备间实时同步文本、图片等内容。

## 功能特性

### 核心功能
- **实时同步** - 基于 WebSocket 的即时同步，一处复制，处处可用
- **端到端加密** - AES-256-GCM 加密，确保数据安全
- **多设备支持** - 支持桌面端、移动端（iOS/Android）同时使用
- **历史记录** - 自动保存最近 200 条剪贴板记录
- **增量同步** - 智能增量同步，节省流量

### 内容类型
| 类型 | 桌面端 | 移动端 | 说明 |
|------|--------|--------|------|
| 文本 | 自动同步 | 手动同步 | 支持任意文本内容 |
| 图片 | 自动同步 | 手动同步 | 支持截图、复制图片 |
| 图文混合 | 自动同步 | 手动同步 | 同时包含文本和图片 |
| 文件 | 规划中 | 规划中 | 大文件支持 |

## 平台兼容性

### 桌面端 (Desktop)
- **macOS** - 完整支持，原生剪贴板监听
- **Windows** - 完整支持，原生剪贴板监听
- **Linux** - 基础支持

### 移动端 (Mobile)
- **iOS** - 支持手动同步，需用户主动触发
- **Android** - 支持手动同步，需用户主动触发

> **注意**：由于 iOS/Android 系统限制，移动端无法实现后台自动监听剪贴板，需要用户点击"同步剪贴板"按钮手动触发。

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                         后端服务 (FastAPI)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ REST API    │  │ WebSocket   │  │ Socket.IO Hub       │  │
│  │ /clipboard  │  │ /ws         │  │ Device Manager      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           │                  │                  │
    ┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐
    │ 桌面端       │    │ 移动端       │    │ Web端       │
    │ (Tauri)     │    │ (Flutter)   │    │ (Browser)   │
    │             │    │             │    │             │
    │ • 自动监听   │    │ • 手动同步   │    │ • 手动同步   │
    │ • 本地缓存   │    │ • 本地缓存   │    │ • 本地缓存   │
    │ • 离线支持   │    │ • 离线支持   │    │ • 离线支持   │
    └─────────────┘    └─────────────┘    └─────────────┘
```

## 项目结构

```
clipboard_core/          # 跨平台核心 SDK (Dart)
├── lib/
│   ├── clipboard_manager.dart      # 主管理器
│   ├── api/clipboard_api_client.dart   # HTTP API 客户端
│   ├── sync/clipboard_sync_service.dart # WebSocket 同步
│   ├── crypto/clipboard_crypto_service.dart # 加密服务
│   ├── models/clipboard_item.dart   # 数据模型
│   └── platform/platform_adapter.dart  # 平台适配接口
└── pubspec.yaml

clipboard_app/           # Flutter 移动端应用
├── lib/
│   ├── screens/clipboard_screen.dart   # 主界面
│   ├── stores/clipboard_store.dart     # 状态管理
│   └── services/flutter_platform_adapter.dart # 平台实现
└── pubspec.yaml
```

## 快速开始

### 后端部署

```bash
# 安装依赖
pip install -r requirements.txt

# 启动服务
python main.py
```

服务默认运行在 `http://localhost:6313`

### 移动端使用

```dart
import 'package:clipboard_core/clipboard_core.dart';

// 1. 创建配置
final config = ClipboardConfig(
  apiBaseUrl: 'http://your-server:6313',
  wsBaseUrl: 'ws://your-server:6313',
  token: 'your-jwt-token',
);

// 2. 初始化管理器
final manager = ClipboardManager(
  config: config,
  platform: YourPlatformAdapter(),
);

// 3. 启动同步
await manager.init();

// 4. 添加文本
await manager.addTextItem('Hello World');

// 5. 添加图片
await manager.addImageItem(
  base64ImageData,
  preview: thumbnailBase64,
);

// 6. 监听同步事件
manager.itemsStream.listen((items) {
  print('收到 ${items.length} 条记录');
});
```

## API 接口

### REST API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/clipboard/history` | 获取历史记录 |
| POST | `/clipboard/add` | 添加剪贴板记录 |
| GET | `/clipboard/sync` | 增量同步 |
| DELETE | `/clipboard/delete/{id}` | 删除单条记录 |
| DELETE | `/clipboard/clear` | 清空历史 |

### WebSocket 事件

| 事件 | 方向 | 说明 |
|------|------|------|
| `register_device` | C→S | 注册设备 |
| `clipboard_sync` | C→S/C←S | 剪贴板同步 |

## 安全说明

1. **端到端加密** - 使用 AES-256-GCM，密钥由用户密码派生
2. **用户隔离** - 数据严格按用户隔离，无法跨用户访问
3. **传输加密** - 支持 HTTPS/WSS 传输
4. **本地存储** - 敏感数据本地加密存储

## 开发计划

- [x] 文本同步
- [x] 图片同步
- [x] 端到端加密
- [x] iOS/Android 支持
- [ ] 文件同步
- [ ] 剪贴板搜索
- [ ] 分类管理
- [ ] 团队协作

## 贡献指南

欢迎提交 Issue 和 PR！

## 许可证

MIT License
