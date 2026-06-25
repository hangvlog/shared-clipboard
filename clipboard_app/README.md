# 共享剪贴板 - 移动端

跨平台剪贴板同步的 Flutter 移动端应用，支持 iOS 和 Android。

## 功能介绍

### 已实现功能
- **账号登录** - JWT 认证，与桌面端共用账号体系
- **剪贴板同步** - 支持文本、图片、图文混合内容
- **实时连接** - WebSocket 实时同步，显示连接状态
- **历史记录** - 本地缓存，支持离线查看
- **端到端加密** - 可选加密，保护隐私数据

### 使用方式

由于 iOS/Android 系统限制，移动端无法实现后台自动监听剪贴板，采用**手动同步**方式：

1. 在其他设备复制内容
2. 打开 App，点击右下角「同步剪贴板」按钮
3. 或下拉刷新获取最新内容
4. 点击列表项即可复制到本机剪贴板

## 开发环境

### 要求
- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Xcode (for iOS)
- Android Studio (for Android)

### 安装依赖

```bash
cd clipboard_app
flutter pub get
```

### 运行开发版

```bash
# iOS 模拟器
flutter run -d ios

# Android 模拟器
flutter run -d android

# 指定设备
flutter run -d <device-id>
```

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── screens/
│   ├── login_screen.dart        # 登录页
│   └── clipboard_screen.dart    # 剪贴板主界面
├── stores/
│   ├── auth_store.dart          # 认证状态
│   └── clipboard_store.dart     # 剪贴板状态
├── services/
│   ├── env_config.dart          # 环境配置
│   └── flutter_platform_adapter.dart  # 平台适配实现
└── widgets/
    └── clipboard_item_tile.dart # 剪贴板列表项
```

## 依赖说明

| 依赖 | 用途 |
|------|------|
| clipboard_core | 核心 SDK（本地路径） |
| super_clipboard | 系统剪贴板访问 |
| sqflite | SQLite 本地存储 |
| provider | 状态管理 |
| device_info_plus | 设备信息 |
| image | 图片处理 |

## 构建发布

### Android

```bash
flutter build apk --release
# 输出: build/app/outputs/flutter-apk/app-release.apk

flutter build appbundle --release
# 输出: build/app/outputs/bundle/release/app-release.aab
```

### iOS

```bash
flutter build ios --release
# 然后在 Xcode 中 Archive 并分发
```

## 注意事项

### iOS 特殊配置

需要在 `ios/Runner/Info.plist` 中添加以下权限声明：

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>需要访问相册以保存图片</string>
```

### Android 特殊配置

最低 SDK 版本要求 21：

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

## 与核心 SDK 的关系

本应用依赖于 `clipboard_core` SDK：

```yaml
dependencies:
  clipboard_core:
    path: ../clipboard_core
```

SDK 提供跨平台通用逻辑：
- API 通信
- WebSocket 连接
- 加密/解密
- 数据模型

本应用提供 Flutter 平台实现：
- 系统剪贴板访问
- SQLite 本地存储
- UI 界面

## 调试技巧

```bash
# 查看日志
flutter logs

# 热重载
flutter run --hot

# 性能分析
flutter run --profile
```

## 常见问题

**Q: 为什么移动端不能自动同步？**  
A: iOS/Android 系统限制，后台应用无法监听剪贴板变化，需用户主动触发。

**Q: 图片同步有限制吗？**  
A: 单张图片建议不超过 5MB，大图片会自动压缩。

**Q: 数据安全吗？**  
A: 支持端到端加密，数据在传输和存储时都经过加密处理。
