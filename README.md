# 共享剪贴板 / Shared Clipboard

独立的多设备剪贴板，使用 ClawKit 同一账号同步；1.1.2 起新文本、图片和图文无需设置加密密码，默认明文保存于服务端，通过 HTTPS 传输并按账号隔离。旧加密记录自动尝试默认密码 123456789、账号已有配置和本机原密码；其他密码可从“解锁旧记录”输入。

## 工程

- `desktop/`：Windows Win32 / macOS AppKit 原生托盘应用，Rust 同步核心。没有常驻 WebView 或 Flutter 引擎。
- `clipboard_app/`：Flutter 安卓、iPhone、iPad 应用。
- `clipboard_core/`：Dart 协议与加密 SDK。
- 服务端唯一维护源：chat-all 的 `routes/clipboard.py`、`routes/ws.py`。本仓 `backend/` 为历史参考，不用于部署。
- CloudDrive 自带的剪贴板是另一个产品中的互通功能，不是本桌面程序。

## 行为与限制

| 设备 | 使用方式 |
|---|---|
| Windows 10/11 x64 | 启动直接打开主窗口，左侧历史、右侧文字/图片预览，复制后可粘贴；关闭后托盘同步，再次启动唤回窗口 |
| Mac ARM / Intel，macOS 10.15+ | 每秒只检查剪贴板版本号，发生变化才读取；睡眠时暂停 |
| Android | 在其他应用复制后切回本应用自动同步；前台变化事件去重同步；后台释放列表并断开连接 |
| iPhone / iPad | 前台点“同步”，后台暂停；iOS 不允许常驻读取其他应用剪贴板；iPad 支持横竖屏 |

文字、PNG/JPEG、图文混合；文本 100KB、图片 2MiB。文件和文件路径不自动同步。历史最多显示最近 50 条摘要。加密文本在前台逐条解密为短预览，点按查看完整正文；图片按需加载。移动端不把解密后的预览写入磁盘；服务端保留最近 200 条。桌面离线队列最多 8 条 / 4MiB，加密落盘，满后明确提示；退出登录会移除该账号待发送队列。移动端不承诺离线发送，失败会提示。

没有调用强制工作集裁剪来制造低内存数字。完整后台仍需系统 GUI/HTTPS/加密资源，不能承诺 1–2MiB。

## 构建

后续安装包在本机 macOS / SSH 受控 Windows 从已推送的准确提交构建；Windows 桌面既有版本在家庭 HANG 构建；本次 Android 修复包按用户要求改用高性能 D-GM12JWEF-1416。GitHub Actions 只保留静态分析和测试，不在标签或 Release 事件自动编译安装包。Android 构建前检查本机或受控 Windows 的既有 Flutter / Android 工具链；iOS 真机分发还需要 Apple Developer 团队与 provisioning。

```sh
cd desktop
cargo test --locked
# macOS universal DMG installer
sh scripts/package-macos.sh
# Windows 在 Visual Studio x64 开发环境构建
cargo build --release --locked
```

Mac 默认交付 `desktop/out/SharedClipboard-1.1.4-macos-universal.dmg`，同时支持 Apple Silicon 与 Intel。打开 DMG 后将 `Shared Clipboard.app` 拖入旁边的 `Applications`，从应用程序启动即可看到历史主窗口；安装后可推出磁盘映像。`desktop/out` 中的 `.app` 只是打包中间产物，不作为下载安装包。预览版仍为 ad-hoc 签名，尚未 Apple 公证。

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

## Android 1.1.1 修复与签名

- 登录后通过现有认证接口 `/auth/encryption-salt` 读取该账号已保存的密码配置，匹配现有 AES-GCM 协议；不上传新密码、不修改服务器数据。读取失败会提示并阻止明文自动上传，刷新可重试。其他密码加密的历史可从菜单手动解锁。
- Android 10+ 普通应用不能在后台读取微信/浏览器剪贴板。`MainActivity` 只在前台监听变化/焦点事件；切回应用后读取最新内容、按摘要去重。无后台服务、轮询或保活。
- 移动端云端新记录更新历史，不自动覆盖手机当前剪贴板，避免切回应用时覆盖刚复制的内容；点击“复制”后抑制回传。
- `CLIENT_LOG_URL` 控制集中诊断端点；仅允许固定事件名和匿名会话 ID，3 秒超时、同事件 30 秒限流、后台关闭连接，不上传正文、账号、密码、Token 或异常字符串。
- 1.1.1 起使用专用固定签名；旧 1.1.0 是临时 CI debug 签名，无法原地覆盖。旧版保留在发布存储，新包安装前需用户自行处理旧版，云端账号历史不受影响。固定签名私钥不进仓库。
- Gradle 未提供 `SHARED_CLIPBOARD_SIGNING_PROPERTIES` 时生成未签名 release，随后通过受控签名步骤签署；不会自动退回随机 debug 签名。该变量也可指向私有 properties 文件，包含 `storeFile/storePassword/keyAlias/keyPassword`。

## 1.1.2 免密同步与旧记录兼容

- 新同步内容固定 `encrypted=false`；读取或输入旧密码不会开启新内容加密。桌面登录只填账号与登录密码。
- 旧 AES-GCM 协议保留，逐个尝试默认密码、账号配置和手动输入的密码；配置不可用不阻止新内容同步。桌面已存的原密钥继续仅用于读取。
- 桌面历史按需逐条读取加密文本，显示短预览；不预载图片，不长期缓存解密正文。
- 不改写生产历史、不修改 CloudDrive 的文件加密；旧客户端仍可能发送加密记录，建议各端升级。
- HTTPS、账号权限、系统凭据保护及离线队列的随机密钥加密保持。统一默认密码仅作旧记录兼容，不作为安全保障。

## Windows 1.1.2 主窗口

启动或再次点击程序即显示主页面；左键点托盘图标可唤回，右键提供账号、暂停和退出操作。最近 50 条记录按需载入，选中后查看全文或图片；点击“复制内容”或双击记录复制，不关闭页面。新同步内容到达时刷新列表并保持所选记录。无记录/未登录时显示操作提示；关闭窗口释放预览和历史，保留托盘同步。

Android 1.1.2 构建工具链固定为 Flutter 3.41.7 / Dart 3.11.5、JDK 17 与 NDK 28.2.13676358（锁定的 JNI 依赖要求）；使用官方构建入口和已锁定 pub 依赖。

剪贴板原生依赖使用其已锁定包内 Cargokit 配置验证的签名预编译库（按源码哈希匹配）；配置在 `clipboard_app/cargokit_options.yaml`，不要求构建机再安装滚动 stable Rust。APK 本身仍在受控 Windows 本地编译与签名发布。
