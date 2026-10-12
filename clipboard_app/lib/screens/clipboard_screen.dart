import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clipboard_core/clipboard_core.dart';
import '../stores/clipboard_store.dart';
import '../stores/auth_store.dart';
import '../widgets/clipboard_item_tile.dart';

/// 剪贴板主页面
class ClipboardScreen extends StatelessWidget {
  const ClipboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    final authStore = context.read<AuthStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('共享剪贴板'),
        actions: [
          // 连接状态指示器
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.circle,
              size: 12,
              color: store.isConnected ? Colors.green : Colors.grey,
            ),
          ),
          // 刷新
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: store.isLoading ? null : () => store.refresh(),
            tooltip: '刷新',
          ),
          // 更多菜单
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'unlock':
                  _unlock(context, store, authStore.username!);
                  break;
                case 'clear':
                  _showClearConfirm(context, store);
                  break;
                case 'logout':
                  authStore.logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'unlock', child: Text('解锁加密剪贴板')),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep),
                    SizedBox(width: 8),
                    Text('清空历史'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('退出登录'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: _buildBody(context, store),
        ),
      ),
      // 悬浮按钮：同步当前剪贴板
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _syncClipboard(context, store),
        icon: const Icon(Icons.content_paste_go),
        label: const Text('同步剪贴板'),
        tooltip: '读取并同步当前剪贴板内容到其他设备',
      ),
    );
  }

  Widget _buildBody(BuildContext context, ClipboardStore store) {
    if (store.isLoading && store.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (store.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.content_paste_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有剪贴板记录',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '同账号电脑端复制后同步；手机端请点击下方按钮',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => store.refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88), // FAB 空间
        itemCount: store.items.length,
        itemBuilder: (context, index) {
          final item = store.items[index];
          return ClipboardItemTile(
            item: item,
            onCopy: () => _copyItem(context, store, item),
            onDelete: () => _confirmDelete(context, store, item),
          );
        },
      ),
    );
  }

  Future<void> _syncClipboard(
    BuildContext context,
    ClipboardStore store,
  ) async {
    try {
      await store.syncCurrentClipboard();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('剪贴板内容已同步'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _copyItem(
    BuildContext context,
    ClipboardStore store,
    ClipboardItem item,
  ) async {
    try {
      await store.copyItem(item);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _unlock(
    BuildContext context,
    ClipboardStore store,
    String username,
  ) async {
    var input = "";
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解锁加密剪贴板'),
        content: TextField(
          onChanged: (value) => input = value,
          obscureText: true,
          decoration: const InputDecoration(labelText: '各设备相同的剪贴板加密密码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, input),
            child: const Text('解锁'),
          ),
        ],
      ),
    );
    if (password != null && password.isNotEmpty) {
      await store.unlock(password, username);
    }
  }

  void _confirmDelete(
    BuildContext context,
    ClipboardStore store,
    ClipboardItem item,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条剪贴板记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              store.deleteItem(item.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showClearConfirm(BuildContext context, ClipboardStore store) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空所有剪贴板历史记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              store.clearHistory();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
