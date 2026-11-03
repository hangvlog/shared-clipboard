import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../stores/update_store.dart';
import 'glass_surface.dart';

/// Update banner above the history list; hidden when there is nothing to act on.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UpdateStore>();
    if (!store.visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final version = store.update?.version ?? '';
    final (title, detail) = switch (store.status) {
      UpdateStatus.downloading => (
        '正在后台下载 $version',
        '${(store.progress * 100).round()}% · 可以退出应用，下载完成后回来安装',
      ),
      UpdateStatus.paused => ('下载已暂停', '等待网络恢复后系统会继续下载'),
      UpdateStatus.ready => ('新版本 $version 已下载', '已校验安装包，点按安装'),
      UpdateStatus.permission => (
        '需要允许安装',
        store.error ?? '在系统设置中允许本应用安装更新，返回后继续',
      ),
      UpdateStatus.installer => ('正在打开系统安装', '按系统提示完成更新'),
      UpdateStatus.error => ('更新未完成', store.error ?? '请重试'),
      _ => (
        '发现新版本 $version',
        store.update?.notes.isNotEmpty == true
            ? store.update!.notes.first
            : '下载在后台进行，可以退出应用',
      ),
    };
    final (label, action) = switch (store.status) {
      UpdateStatus.downloading || UpdateStatus.paused => ('取消', store.cancel),
      UpdateStatus.ready ||
      UpdateStatus.permission ||
      UpdateStatus.installer => (
        store.status == UpdateStatus.permission ? '继续安装' : '安装',
        store.install,
      ),
      _ => ('下载更新', store.download),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GlassSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.system_update_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(onPressed: () => action(), child: Text(label)),
              ],
            ),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (store.status == UpdateStatus.downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: store.progress > 0 ? store.progress : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Manual check from the menu; reports the result in a snackbar.
Future<void> checkForUpdates(BuildContext context) async {
  final store = context.read<UpdateStore>();
  final messenger = ScaffoldMessenger.of(context);
  await store.check();
  final text = switch (store.status) {
    UpdateStatus.latest => '已是最新版本',
    UpdateStatus.error => store.error ?? '检查更新失败',
    _ => '发现新版本 ${store.update?.version ?? ''}',
  };
  messenger.showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
  );
}
