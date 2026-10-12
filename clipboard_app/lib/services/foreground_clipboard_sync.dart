import 'dart:async';
import 'package:clipboard_core/clipboard_core.dart';

/// Event-driven foreground sync, with echo suppression for cloud clipboard writes.
class ForegroundClipboardSync {
  final Future<ClipboardContent?> Function() read;
  final Future<void> Function(ClipboardContent) send;
  final void Function(String) status;
  bool enabled = false;
  bool _busy = false;
  bool _writing = false;
  bool _again = false;
  int _generation = 0;
  String? _lastHash;
  Timer? _debounce;
  ForegroundClipboardSync({
    required this.read,
    required this.send,
    required this.status,
  });

  void changed() {
    if (!enabled || _writing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), sync);
  }

  Future<void> sync() async {
    if (!enabled || _writing) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    final generation = _generation;
    try {
      final content = await read();
      if (!enabled ||
          generation != _generation ||
          content == null ||
          content.hash == _lastHash) {
        return;
      }
      await send(content);
      if (!enabled || generation != _generation) return;
      _lastHash = content.hash;
      status('剪贴板已自动同步');
    } catch (_) {
      if (enabled && generation == _generation) status('自动同步失败，请点按重试');
    } finally {
      _busy = false;
      if (_again && enabled) {
        _again = false;
        changed();
      }
    }
  }

  Future<void> suppressDuring(Future<void> Function() write) async {
    _writing = true;
    _generation++;
    _debounce?.cancel();
    try {
      await write();
      if (enabled) await suppressCurrent();
    } finally {
      _writing = false;
    }
  }

  Future<void> suppressCurrent() async {
    final generation = _generation;
    final content = await read();
    if (generation == _generation) _lastHash = content?.hash;
  }

  void pause() {
    enabled = false;
    _generation++;
    _again = false;
    _debounce?.cancel();
  }

  void dispose() {
    pause();
    _lastHash = null;
  }
}
