import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:clipboard_core/clipboard_core.dart';

Future<void> showClipboardDetail(
  BuildContext context, {
  required Future<ClipboardItem> Function() read,
  required Future<void> Function(ClipboardItem) copy,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ClipboardDetail(read: read, copy: copy),
);

class _ClipboardDetail extends StatefulWidget {
  final Future<ClipboardItem> Function() read;
  final Future<void> Function(ClipboardItem) copy;
  const _ClipboardDetail({required this.read, required this.copy});
  @override
  State<_ClipboardDetail> createState() => _ClipboardDetailState();
}

class _ClipboardDetailState extends State<_ClipboardDetail>
    with WidgetsBindingObserver {
  ClipboardItem? _item;
  String? _error;
  bool _closed = false;
  bool _copying = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final item = await widget.read();
      if (mounted && !_closed) setState(() => _item = item);
    } catch (_) {
      if (mounted && !_closed) {
        setState(() => _error = '无法读取内容，请检查网络或使用原加密密码解锁');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _closed = true;
      _item = null;
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _item = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _copy() async {
    final item = _item;
    if (item == null || _copying) return;
    setState(() => _copying = true);
    try {
      await widget.copy(item);
      if (mounted && !_closed) Navigator.of(context).pop();
    } catch (_) {
      if (mounted && !_closed) {
        setState(() {
          _error = '复制失败，请重试';
          _copying = false;
        });
      }
    }
  }

  Widget _image(String source) {
    if (source.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(source.split(',').last),
          fit: BoxFit.contain,
          cacheWidth: 960,
        );
      } catch (_) {}
    }
    if (source.startsWith('https://')) {
      return Image.network(
        source,
        fit: BoxFit.contain,
        cacheWidth: 960,
        errorBuilder: (_, _, _) => const Text('图片加载失败'),
      );
    }
    return const Text('该图片格式暂不支持显示');
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return AlertDialog(
      title: const Text('内容预览'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) Text(_error!),
              if (item == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (item != null && item.contentType != 'image')
                SelectableText(item.content),
              if (item != null && item.contentType == 'image')
                _image(item.content),
              if (item?.contentType == 'rich' && item?.imageUrl != null)
                _image(item!.imageUrl!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: item == null || _copying ? null : _copy,
          child: const Text('复制'),
        ),
      ],
    );
  }
}
