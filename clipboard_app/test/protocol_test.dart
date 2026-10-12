import 'dart:convert';
import 'dart:async';
import 'package:clipboard_app/services/foreground_clipboard_sync.dart';
import 'package:clipboard_app/services/mobile_diagnostics.dart';
import 'package:http/testing.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_core/clipboard_core.dart';

class MemoryPlatform extends PlatformAdapter {
  List<ClipboardItem> cached = [];
  String? copied;
  @override
  Future<void> initStorage() async {}
  @override
  Future<List<ClipboardItem>> getAllCachedItems() async => cached;
  @override
  Future<void> replaceAllCached(List<ClipboardItem> items) async {
    cached = items;
  }

  @override
  Future<void> upsertItems(List<ClipboardItem> items) async {
    cached.addAll(items);
  }

  @override
  Future<void> setLastSyncTime(String time) async {}
  @override
  Future<void> writeClipboardText(String text) async {
    copied = text;
  }

  @override
  String getDeviceId() => 'test-phone';
  @override
  String getDeviceName() => 'Android test';
  @override
  String getDeviceType() => 'mobile';
  @override
  String getPlatformName() => 'android';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Unlocked encrypted history shows readable text without copying or plaintext disk cache',
    () async {
      final crypto = ClipboardCryptoService();
      await crypto.deriveKeyFromUsername('密码+fixture %', 'fixture-user');
      final raw = ClipboardItem(
        id: 'one',
        content: crypto.encryptText('同账号可见'),
        contentType: 'text',
        deviceId: 'other-device',
        deviceName: 'Mac',
        createdAt: '2026-10-12T12:00:00Z',
        encrypted: true,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        expect(request.headers.value('authorization'), 'Bearer synthetic');
        final dynamic data = request.uri.path.endsWith('/encryption-salt')
            ? {
                'password': base64Encode(
                  utf8.encode(Uri.encodeComponent('密码+fixture %')),
                ),
              }
            : request.uri.path.endsWith('/history')
            ? [raw.copyWith(content: '', metadataOnly: true).toJson()]
            : raw.toJson();
        request.response.write(jsonEncode({'code': 200, 'data': data}));
        await request.response.close();
      });
      final platform = MemoryPlatform();
      final base = 'http://127.0.0.1:${server.port}';
      final manager = ClipboardManager(
        config: ClipboardConfig(
          apiBaseUrl: base,
          wsBaseUrl: base,
          token: 'synthetic',
        ),
        platform: platform,
        accountUsername: 'fixture-user',
        autoCopyRemote: false,
      );
      try {
        await manager.restoreAccountEncryption();
        await manager.syncWithServer();
        expect(manager.items.single.content, '同账号可见');
        expect(platform.cached.single.content, isNot(contains('同账号可见')));
        expect(platform.copied, isNull);
        final full = await manager.readItem(manager.items.single);
        expect(full.content, '同账号可见');
        expect(full.metadataOnly, isFalse);
        await manager.copyToClipboard(manager.items.single);
        expect(platform.copied, '同账号可见');
        await manager.setEncryptionKey('wrong-password', 'fixture-user');
        expect(manager.items.single.encrypted, isTrue);
        await expectLater(
          manager.copyToClipboard(manager.items.single),
          throwsStateError,
        );
        expect(platform.copied, '同账号可见');
        manager.suspend();
        expect(manager.items, isEmpty);
      } finally {
        manager.dispose();
        await server.close(force: true);
      }
    },
  );
  test(
    'Android resume sync is deduplicated, paused in background and does not echo cloud writes',
    () async {
      var current = ClipboardContent(
        contentType: 'text',
        text: 'other app',
        hash: 'one',
      );
      var reads = 0;
      final sent = <String>[];
      final sync = ForegroundClipboardSync(
        read: () async {
          reads++;
          return current;
        },
        send: (item) async {
          sent.add(item.text!);
        },
        status: (_) {},
      );
      await sync.sync();
      expect(reads, 0);
      sync.enabled = true;
      await sync.sync();
      await sync.sync();
      expect(sent, ['other app']);
      sync.pause();
      current = ClipboardContent(
        contentType: 'text',
        text: 'WeChat new',
        hash: 'two',
      );
      final pausedReads = reads;
      sync.changed();
      await sync.sync();
      expect(reads, pausedReads);
      sync.enabled = true;
      await sync.sync();
      expect(sent, ['other app', 'WeChat new']);
      await sync.suppressDuring(() async {
        current = ClipboardContent(
          contentType: 'text',
          text: 'cloud copy',
          hash: 'three',
        );
        sync.changed();
        await sync.sync();
      });
      await sync.sync();
      expect(sent, ['other app', 'WeChat new']);
      sync.dispose();
    },
  );
  test('Clipboard read completing after pause cannot upload', () async {
    final pending = Completer<ClipboardContent?>();
    var sent = 0;
    final sync = ForegroundClipboardSync(
      read: () => pending.future,
      send: (_) async {
        sent++;
      },
      status: (_) {},
    );
    sync.enabled = true;
    final work = sync.sync();
    sync.pause();
    pending.complete(
      ClipboardContent(contentType: 'text', text: 'late', hash: 'late'),
    );
    await work;
    expect(sent, 0);
    sync.dispose();
  });
  test(
    'Account configuration failure blocks plaintext upload and can retry',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var configOk = false;
      var posts = 0;
      server.listen((request) async {
        if (request.method == 'POST') posts++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'code': configOk ? 200 : 500,
            'data': request.uri.path.endsWith('/history')
                ? []
                : {'password': null},
          }),
        );
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final manager = ClipboardManager(
        config: ClipboardConfig(
          apiBaseUrl: base,
          wsBaseUrl: base,
          token: 'synthetic',
        ),
        platform: MemoryPlatform(),
        accountUsername: 'fixture',
      );
      try {
        await manager.restoreAccountEncryption();
        expect(manager.encryptionNotice, isNotNull);
        await expectLater(manager.addTextItem('private'), throwsStateError);
        expect(posts, 0);
        configOk = true;
        await manager.restoreAccountEncryption();
        expect(manager.encryptionNotice, isNull);
      } finally {
        manager.dispose();
        await server.close(force: true);
      }
    },
  );
  test(
    'Diagnostics allowlist, rate limit and network failure are isolated',
    () async {
      final records = <Map<String, dynamic>>[];
      var calls = 0;
      final logs = MobileDiagnostics(
        endpoint: 'https://example.invalid/report',
        clientFactory: () => MockClient((request) async {
          calls++;
          records.add(jsonDecode(request.body) as Map<String, dynamic>);
          throw const SocketException('synthetic private response');
        }),
      );
      await logs.report(MobileEvent.readFailed);
      await logs.report(MobileEvent.readFailed);
      expect(calls, 1);
      expect(records.single['message'], 'readFailed');
      expect(records.single.keys, isNot(contains('detail')));
      expect(records.single.toString(), isNot(contains('synthetic private')));
      expect(
        (records.single['sessionId'] as String).length,
        lessThanOrEqualTo(64),
      );
      logs.pause();
      await logs.report(MobileEvent.autoSynced);
      expect(calls, 1);
      logs.resume();
      await logs.report(MobileEvent.autoSynced);
      expect(calls, 2);
      logs.dispose();
      await logs.report(MobileEvent.initialized);
      expect(calls, 2);
    },
  );
  test('Shared native/Dart encryption protocol vector', () async {
    final crypto = ClipboardCryptoService();
    await crypto.deriveKeyFromUsername('cross-platform-password', 'fixture-a');
    expect(
      crypto.decryptText(
        'AAECAwQFBgcICQoLDv7L0NrdVkdC+ltn7/sFX4vg5WGuh4bQkgGbBb+qps5Osc3qiKfycWIUlJL3Zg==',
      ),
      'Windows Mac 安卓 iPhone iPad',
    );
    await crypto.deriveKeyFromUsername('wrong', 'fixture-a');
    expect(
      () => crypto.decryptText(
        'AAECAwQFBgcICQoLDv7L0NrdVkdC+ltn7/sFX4vg5WGuh4bQkgGbBb+qps5Osc3qiKfycWIUlJL3Zg==',
      ),
      throwsA(anything),
    );
  });
}
