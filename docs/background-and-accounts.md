# 共享剪贴板 1.0.1

本 Flutter 工程是共享剪贴板的手机端，Windows/Mac 实现位于 `hangvlog/cloud-drive`（Tauri + React）。生产统一使用 `https://clawkit.chat/api` 和 `https://clawkit.chat` Socket.IO。同一登录账号共享，异账号隔离。手机手动点击同步，后台不承诺持续采集；回前台重连并补拉最多 200 条。

本次变更：按账号独立 SQLite 和同步游标；退出/切号取消订阅、销毁 Socket.IO 并清空内存；旧请求通过代次检查避免写回新账号；退后台暂停连接、清理图片缓存，缩略图解码限制宽度 400；每个缓存最多 200 条。历史同步使用有上限的快照，修复删除后本地内容不一致。

电脑端加密过的记录需要相同云盘加密密码。手机右上角菜单「解锁加密剪贴板」输入该密码，仅本次登录内存持有派生密钥，不持久化密码。没有密钥或解密失败的记录保持加密状态，不自动复制占位文字。加密 IV 使用系统安全随机数。

文本与图片有上传入口。图片读入使用 super_clipboard 文件格式 API，修复原先 PNG/JPEG 强制转换为 ValueFormat 导致读取失败。图片仍受现有后端 100KB 内容上限，手机大图片上传与图文混合保留文字尚有限制；未宣称这部分已完善。手机图片复制尚未实现。

验证：登录页 Flutter widget 测试；Dart 定向分析；主服务实际 HTTP/Socket.IO 的双账号三设备隔离。iOS 本机编译受 Xcode 模拟器平台缺失限制，不把 widget 测试等同于 iPhone 真机验收。Android 通过 release workflow 构建，iOS 无签名构建不能作为可安装 IPA。

构建固定 Flutter 3.41.7 / Dart 3.11.5，使用已提交锁文件；生产包需 `--dart-define=ENV=production`。桌面发包按统一 ssh-windows-control 的 `--device hang` 在个人 HANG 构建。
