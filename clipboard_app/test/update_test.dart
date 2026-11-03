import 'dart:convert';
import 'package:clipboard_app/services/android_updater.dart';
import 'package:clipboard_app/services/app_update.dart';
import 'package:clipboard_app/stores/update_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const sha = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Map<String, dynamic> manifest({
  bool hasUpdate = true,
  String version = '1.1.13',
  String url = 'https://clawkit.chat/x.apk',
  String hash = sha,
  int size = 1024,
}) => {
  'has_update': hasUpdate,
  'mandatory': false,
  'latest': {
    'version': version,
    'notes': ['修复更新'],
  },
  'artifact': {'platform': 'android', 'url': url, 'sha256': hash, 'size': size},
};

class FakeApi extends AppUpdateApi {
  FakeApi(this.result);
  Object result;
  final asked = <String>[];
  @override
  Future<AppUpdate> check(String currentVersion) async {
    asked.add(currentVersion);
    if (result is Exception) throw result;
    return result as AppUpdate;
  }
}

class FakeUpdater extends AndroidUpdater {
  DownloadState state = DownloadState('idle');
  String installResult = 'permission';
  bool allowed = false;
  final calls = <String>[];
  @override
  Future<String> installedVersion() async => '1.1.12';
  @override
  Future<DownloadState> snapshot() async => state;
  @override
  Future<DownloadState> download(
    String url,
    String sha256,
    int size,
    String version,
  ) async {
    calls.add('download $version $size');
    return state = DownloadState(
      'downloading',
      version: version,
      sha256: sha256,
      received: 256,
      total: size,
    );
  }

  @override
  Future<String> install() async {
    calls.add('install');
    return installResult;
  }

  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> cancel() async => state = DownloadState('idle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Installable update requires https, a SHA-256 and a sane size', () {
    AppUpdate.fromJson(manifest()).validateInstallable();
    for (final bad in [
      manifest(url: 'http://clawkit.chat/x.apk'),
      manifest(url: 'https://user:pw@clawkit.chat/x.apk'),
      manifest(hash: 'abc'),
      manifest(size: 0),
      manifest(size: 300 * 1024 * 1024),
      manifest(version: '1.1'),
      manifest(hasUpdate: false),
    ]) {
      expect(
        () => AppUpdate.fromJson(bad).validateInstallable(),
        throwsStateError,
      );
    }
  });

  test(
    'Check asks the platform-aware endpoint with the installed version',
    () async {
      late Uri seen;
      final api = AppUpdateApi(
        baseUrl: 'https://clawkit.chat/api',
        clientFactory: () => MockClient((request) async {
          seen = request.url;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'code': 200, 'data': manifest()})),
            200,
          );
        }),
      );
      final update = await api.check('1.1.12');
      expect(seen.path, '/api/releases/shared-clipboard/update');
      expect(seen.queryParameters, {
        'current_version': '1.1.12',
        'platform': 'android',
        'arch': 'universal',
        'channel': 'preview',
      });
      expect(update.hasUpdate, isTrue);
      expect(update.version, '1.1.13');
      expect(update.notes, ['修复更新']);
    },
  );

  test(
    'Download runs in the background, then installs after permission is granted',
    () async {
      final updater = FakeUpdater();
      final store = UpdateStore(
        api: FakeApi(AppUpdate.fromJson(manifest())),
        updater: updater,
        enabled: true,
      );
      await store.check();
      expect(store.status, UpdateStatus.available);
      expect(store.visible, isTrue);
      await store.download();
      expect(updater.calls, ['download 1.1.13 1024']);
      expect(store.status, UpdateStatus.downloading);
      expect(store.progress, 0.25);
      updater.state = DownloadState(
        'ready',
        version: '1.1.13',
        sha256: sha,
        received: 1024,
        total: 1024,
      );
      await store.install();
      expect(store.status, UpdateStatus.permission);
      updater
        ..allowed = true
        ..installResult = 'installer';
      store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(updater.calls.where((c) => c == 'install').length, 2);
      expect(store.status, UpdateStatus.installer);
      store.dispose();
    },
  );

  test(
    'A leftover download of another release is ignored; silent failures stay quiet',
    () async {
      final updater = FakeUpdater()
        ..state = DownloadState('ready', version: '1.1.12', sha256: sha);
      final api = FakeApi(AppUpdate.fromJson(manifest()));
      final store = UpdateStore(api: api, updater: updater, enabled: true);
      await store.check();
      expect(store.status, UpdateStatus.available);
      expect(api.asked.last, '1.1.12');
      api.result = Exception('offline');
      final quiet = UpdateStore(api: api, updater: updater, enabled: true);
      await quiet.check(silent: true);
      expect(quiet.status, UpdateStatus.idle);
      expect(quiet.visible, isFalse);
      await quiet.check();
      expect(quiet.status, UpdateStatus.error);
      store.dispose();
      quiet.dispose();
    },
  );

  test('Latest version hides the card', () async {
    final store = UpdateStore(
      api: FakeApi(AppUpdate.fromJson(manifest(hasUpdate: false))),
      updater: FakeUpdater(),
      enabled: true,
    );
    await store.check();
    expect(store.status, UpdateStatus.latest);
    expect(store.visible, isFalse);
    store.dispose();
  });
}
