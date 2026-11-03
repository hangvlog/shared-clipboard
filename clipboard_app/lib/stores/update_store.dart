import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../services/android_updater.dart';
import '../services/app_update.dart';

enum UpdateStatus {
  idle,
  checking,
  latest,
  available,
  downloading,
  paused,
  ready,
  permission,
  installer,
  error,
}

/// Android in-app update, following ClawKit Mobile: the system downloads in the
/// background (notification, survives leaving the app); installing always needs
/// a foreground tap and the system installer.
class UpdateStore extends ChangeNotifier with WidgetsBindingObserver {
  UpdateStore({
    AppUpdateApi? api,
    AndroidUpdater? updater,
    bool? enabled,
    this.recheckAfter = const Duration(hours: 6),
  }) : _api = api ?? AppUpdateApi(),
       _updater = updater ?? AndroidUpdater(),
       enabled = enabled ?? Platform.isAndroid {
    if (!this.enabled) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check(silent: true));
  }

  final AppUpdateApi _api;
  final AndroidUpdater _updater;
  final bool enabled;
  final Duration recheckAfter;

  UpdateStatus status = UpdateStatus.idle;
  AppUpdate? update;
  String? error;
  double progress = 0;
  DateTime? _checkedAt;
  bool _installing = false, _awaitingPermission = false;
  Future<void>? _inflight;
  bool _lastFailed = false;
  bool _disposed = false;
  Timer? _poll;

  /// Shown above the history list while there is something to act on.
  bool get visible =>
      enabled && update?.hasUpdate == true && status != UpdateStatus.latest;

  /// A manual check during an automatic one waits for it, then reports its outcome.
  Future<void> check({bool silent = false}) async {
    if (!enabled || _installing) return;
    final running = _inflight;
    if (running != null) {
      await running;
      if (silent) return;
      if (_lastFailed) return check();
      if (update?.hasUpdate == false) _set(UpdateStatus.latest);
      return;
    }
    final current = _inflight = _check(silent);
    try {
      await current;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _check(bool silent) async {
    if (!silent) _set(UpdateStatus.checking);
    _lastFailed = false;
    try {
      final result = await _api.check(await _updater.installedVersion());
      final state = await _updater.snapshot();
      _checkedAt = DateTime.now();
      update = result;
      error = null;
      if (!result.hasUpdate) {
        _set(silent ? UpdateStatus.idle : UpdateStatus.latest);
      } else if (!_apply(state)) {
        _set(UpdateStatus.available);
      }
    } catch (e) {
      _lastFailed = true;
      if (!silent) _fail(e);
    }
  }

  Future<void> download() async {
    final release = update;
    if (release == null) return;
    try {
      release.validateInstallable();
      final state = await _updater.download(
        release.url!,
        release.sha256!,
        release.size!,
        release.version!,
      );
      if (!_apply(state)) _set(UpdateStatus.downloading);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> install() async {
    if (update == null || _installing) return;
    _installing = true;
    try {
      final state = await _updater.snapshot();
      if (!_matches(state) || state.stage != 'ready') {
        _apply(state);
        return;
      }
      final result = await _updater.install();
      _awaitingPermission = result == 'permission';
      _set(
        _awaitingPermission ? UpdateStatus.permission : UpdateStatus.installer,
      );
    } catch (e) {
      _fail(e);
    } finally {
      _installing = false;
    }
  }

  Future<void> cancel() async {
    try {
      await _updater.cancel();
      progress = 0;
      error = null;
      _set(UpdateStatus.available);
    } catch (e) {
      _fail(e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _poll?.cancel();
      return;
    }
    if (_awaitingPermission) {
      _awaitingPermission = false;
      unawaited(
        _updater
            .canInstall()
            .then((allowed) {
              if (allowed) return install();
              error = '尚未允许安装更新。点按“继续安装”后，在系统设置中允许本应用安装。';
              _set(UpdateStatus.permission);
            })
            .catchError((Object _) => _set(UpdateStatus.ready)),
      );
      return;
    }
    final due =
        _checkedAt == null ||
        DateTime.now().difference(_checkedAt!) >= recheckAfter;
    if (due) {
      unawaited(check(silent: true));
    } else if (update?.hasUpdate == true) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    try {
      _apply(await _updater.snapshot());
    } catch (e) {
      _fail(e);
    }
  }

  bool _matches(DownloadState s) =>
      s.version == update?.version && s.sha256 == update?.sha256;

  /// Adopts a native download that belongs to the current release.
  bool _apply(DownloadState s) {
    if (!_matches(s) || s.stage == 'idle') return false;
    progress = s.progress;
    error = s.error;
    _set(switch (s.stage) {
      'downloading' => UpdateStatus.downloading,
      'paused' => UpdateStatus.paused,
      'ready' => UpdateStatus.ready,
      _ => UpdateStatus.error,
    });
    return true;
  }

  void _set(UpdateStatus next) {
    if (_disposed) return;
    status = next;
    final transferring =
        next == UpdateStatus.downloading || next == UpdateStatus.paused;
    if (transferring && (_poll == null || !_poll!.isActive)) {
      _poll = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _refresh(),
      );
    } else if (!transferring) {
      _poll?.cancel();
    }
    notifyListeners();
  }

  void _fail(Object e) {
    error = switch (e) {
      PlatformException(:final message) => message ?? '更新失败，请重试',
      StateError(:final message) => message,
      _ => '更新失败，请重试',
    };
    _set(UpdateStatus.error);
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    if (enabled) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
