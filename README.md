# 共享剪贴板 / Shared Clipboard

独立的多设备剪贴板，使用 ClawKit 同一账号同步；可选 AES-256-GCM 加密，各端须填写相同剪贴板密码。

## 工程

- `desktop/`：Windows Win32 / macOS AppKit 原生托盘应用，Rust 同步核心。没有常驻 WebView 或 Flutter 引擎。
- `clipboard_app/`：Flutter 安卓、iPhone、iPad 应用。
- `clipboard_core/`：Dart 协议与加密 SDK。
- 服务端唯一维护源：chat-all 的 `routes/clipboard.py`、`routes/ws.py`。本仓 `backend/` 为历史参考，不用于部署。
- CloudDrive 自带的剪贴板是另一个产品中的互通功能，不是本桌面程序。

## 行为与限制

| 设备 | 使用方式 |
|---|---|
| Windows 10/11 x64 | 原生系统通知自动同步，托盘打开登录/历史 |
| Mac ARM / Intel，macOS 10.15+ | 每秒只检查剪贴板版本号，发生变化才读取；睡眠时暂停 |
| Android | 前台点“同步”，接收同账号记录；后台释放列表并断开连接 |
| iPhone / iPad | 同上，iOS 不允许常驻读取其他应用剪贴板；iPad 支持横竖屏 |

文字、PNG/JPEG、图文混合；文本 100KB、图片 2MiB。文件和文件路径不自动同步。历史最多显示最近 50 条摘要，点按才取正文；服务端保留最近 200 条。桌面离线队列最多 8 条 / 4MiB，加密落盘，满后明确提示；退出登录会移除该账号待发送队列。移动端不承诺离线发送，失败会提示。

没有调用强制工作集裁剪来制造低内存数字。完整后台仍需系统 GUI/HTTPS/加密资源，不能承诺 1–2MiB。

## 构建

后续安装包在本机 macOS / SSH 受控 Windows 从已推送的准确提交构建；本产品 Windows 使用用户指定的家庭 HANG（`ssh-windows-control --device hang`）。GitHub Actions 只保留静态分析和测试，不在标签或 Release 事件自动编译安装包。Android 构建前检查本机或受控 Windows 的既有 Flutter / Android 工具链；iOS 真机分发还需要 Apple Developer 团队与 provisioning。

```sh
cd desktop
cargo test --locked
# macOS universal app
sh scripts/package-macos.sh
# Windows 在 Visual Studio x64 开发环境构建
cargo build --release --locked
```

```sh
cd clipboard_app
flutter pub get --enforce-lockfile
flutter test --no-pub
flutter build apk --release --dart-define=ENV=production
flutter build ios --release --no-codesign --dart-define=ENV=production
```

`qa` Cargo feature 仅用于隔离测试，不进入发布构建。测试状态要求 loopback 服务；公开包使用系统 Keychain / Windows DPAPI 保护登录凭据，待发送正文使用独立随机 AES-GCM 密钥加密。

## 发布状态

1.1.0 为原生桌面首个预览版。Android 沿用项目现有 debug 签名，仅供测试；iOS/iPadOS 未配置 Apple Developer 签名，CI 无签名编译成功也不等于有可安装 IPA。macOS 包采用本地 ad-hoc 签名，尚未 Apple 公证；Windows 包尚未代码签名。实际构建与验收记录见 chat-all `docs/front/shared-clipboard-native-1.1.0.md`。

本次已启动并完成的 Android/iOS 云端作业保留其固定源码及产物来源，不重复编译；后续构建按上述本机/受控设备规则执行。
