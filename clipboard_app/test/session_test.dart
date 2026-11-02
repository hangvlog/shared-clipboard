import 'dart:convert';
import 'dart:io';
import 'package:clipboard_app/services/session_api.dart';
import 'package:clipboard_app/stores/auth_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSessions {
  late HttpServer server;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  int accessSeconds = 86400;
  int refreshStatus = 200;
  int issued = 0;

  String get base => 'http://127.0.0.1:${server.port}/codex-remote/sso';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path.split('/').last;
      calls.add(path);
      bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.headers.contentType = ContentType.json;
      if (path == 'refresh' && refreshStatus != 200) {
        request.response.statusCode = refreshStatus;
        request.response.write(jsonEncode({'detail': '远程登录已过期或被撤销，请重新登录'}));
      } else if (path == 'logout') {
        request.response.write(jsonEncode({'revoked': true}));
      } else {
        issued++;
        request.response.write(
          jsonEncode({
            'token': 'access-$issued',
            'refresh_token': 'sid.refresh-secret',
            'expires_in': accessSeconds,
            'user': {'username': 'hang', 'nickname': 'Hang'},
          }),
        );
      }
      await request.response.close();
    });
  }
}

void main() {
  late FakeSessions fake;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fake = FakeSessions();
    await fake.start();
  });
  tearDown(() => fake.server.close(force: true));

  Future<AuthStore> signedIn() async {
    final auth = AuthStore(api: SessionApi(baseUrl: fake.base));
    expect(await auth.login('15700000000', 'secret'), isNull);
    return auth;
  }

  test(
    'Login keeps a device-bound refresh credential for the shared-clipboard client',
    () async {
      final auth = await signedIn();
      expect(auth.token, 'access-1');
      expect(auth.username, 'hang');
      expect(auth.canRenew, isTrue);
      expect(fake.bodies.single['client'], 'shared-clipboard');
      final deviceId = fake.bodies.single['device_id'] as String;
      expect(deviceId.length, greaterThanOrEqualTo(8));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_refresh_token'), 'sid.refresh-secret');
      expect(prefs.getString('clipboard_device_id'), deviceId);
      expect(prefs.getString('auth_last_login'), '15700000000');
    },
  );

  test(
    'Expiring token renews automatically and concurrent renewals share one request',
    () async {
      fake.accessSeconds = 60;
      final auth = await signedIn();
      await Future.wait([auth.ensureFresh(), auth.renew(), auth.renew()]);
      expect(fake.calls.where((c) => c == 'refresh').length, 1);
      expect(auth.token, 'access-2');
      expect(fake.bodies.last['refresh_token'], 'sid.refresh-secret');
      fake.accessSeconds = 86400;
      await auth.renew();
      final before = fake.calls.length;
      await auth.ensureFresh();
      expect(fake.calls.length, before);
      expect(auth.isLoggedIn, isTrue);
    },
  );

  test(
    'Network failure keeps the session; server rejection returns to login',
    () async {
      final auth = await signedIn();
      fake.refreshStatus = 502;
      expect(await auth.renew(), isFalse);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.sessionNotice, isNull);
      fake.refreshStatus = 401;
      expect(await auth.renew(), isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.sessionNotice, '登录已过期，请重新登录');
      expect(auth.lastLogin, '15700000000');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_refresh_token'), isNull);
    },
  );

  test(
    'Saved session survives restart and logout revokes it on the server',
    () async {
      await signedIn();
      final restored = AuthStore(api: SessionApi(baseUrl: fake.base));
      await restored.ensureFresh();
      expect(restored.token, 'access-1');
      expect(restored.canRenew, isTrue);
      await restored.logout();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fake.calls.last, 'logout');
      expect(fake.bodies.last['refresh_token'], 'sid.refresh-secret');
      expect(restored.isLoggedIn, isFalse);
      expect(restored.sessionNotice, isNull);
    },
  );

  test('Wrong password shows the server message', () async {
    await fake.server.close(force: true);
    fake.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fake.server.listen((request) async {
      request.response.statusCode = 401;
      request.response.write(jsonEncode({'detail': '账号或密码错误'}));
      await request.response.close();
    });
    final auth = AuthStore(api: SessionApi(baseUrl: fake.base));
    expect(await auth.login('hang', 'wrong'), '账号或密码错误');
    expect(auth.isLoggedIn, isFalse);
  });
}
