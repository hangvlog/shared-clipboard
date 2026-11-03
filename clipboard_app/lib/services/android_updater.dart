import 'package:flutter/services.dart';

/// Native download state; `stage` is idle, downloading, paused, ready or error.
class DownloadState {
  DownloadState(
    this.stage, {
    this.version,
    this.sha256,
    this.received = 0,
    this.total = 0,
    this.error,
  });
  final String stage;
  final String? version;
  final String? sha256;
  final int received;
  final int total;
  final String? error;

  factory DownloadState.fromMap(Map<Object?, Object?>? map) {
    final m = map ?? const {};
    return DownloadState(
      (m['stage'] as String?) ?? 'idle',
      version: m['version'] as String?,
      sha256: m['sha256'] as String?,
      received: (m['received'] as num?)?.toInt() ?? 0,
      total: (m['total'] as num?)?.toInt() ?? 0,
      error: m['error'] as String?,
    );
  }

  double get progress =>
      total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;
}

/// `chat.clawkit.clipboard/updater` (see AppUpdater.kt).
class AndroidUpdater {
  AndroidUpdater([MethodChannel? channel])
    : _channel =
          channel ?? const MethodChannel('chat.clawkit.clipboard/updater');
  final MethodChannel _channel;

  Future<String> installedVersion() async {
    final info = await _channel.invokeMapMethod<String, Object?>('version');
    return (info?['name'] as String?) ?? '0.0.0';
  }

  Future<DownloadState> snapshot() async => DownloadState.fromMap(
    await _channel.invokeMapMethod<Object?, Object?>('snapshot'),
  );

  Future<DownloadState> download(
    String url,
    String sha256,
    int size,
    String version,
  ) async => DownloadState.fromMap(
    await _channel.invokeMapMethod<Object?, Object?>('download', {
      'url': url,
      'sha256': sha256,
      'size': size,
      'version': version,
    }),
  );

  /// `permission` (sent to system settings) or `installer` (system installer opened).
  Future<String> install() async =>
      (await _channel.invokeMethod<String>('install')) ?? 'installer';

  Future<bool> canInstall() async =>
      (await _channel.invokeMethod<bool>('canInstall')) ?? false;

  Future<void> cancel() => _channel.invokeMethod('cancel');
}
