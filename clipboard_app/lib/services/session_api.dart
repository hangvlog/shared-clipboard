import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env_config.dart';

/// Access token plus the long-lived, device-bound refresh credential.
class SessionGrant {
  SessionGrant({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    this.username,
    this.nickname,
  });
  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final String? username;
  final String? nickname;
}

/// The server refused the credentials or the session was revoked/expired.
class SessionRejected implements Exception {
  SessionRejected(this.message);
  final String message;
}

/// Network or server trouble; the saved session stays valid and is retried later.
class SessionUnavailable implements Exception {
  SessionUnavailable(this.message);
  final String message;
}

/// Revocable account sessions shared with ClawKit native clients (`/codex-remote/sso`).
class SessionApi {
  SessionApi({String? baseUrl, http.Client Function()? clientFactory})
    : _baseUrl = baseUrl ?? '${EnvConfig.apiBaseUrl}/codex-remote/sso',
      _clientFactory = clientFactory ?? http.Client.new;
  final String _baseUrl;
  final http.Client Function() _clientFactory;

  Future<SessionGrant> login(
    String username,
    String password,
    String deviceId,
  ) => _grant('/password', {
    'username': username,
    'password': password,
    'device_id': deviceId,
    'client': 'shared-clipboard',
  });

  Future<SessionGrant> refresh(String refreshToken, String deviceId) => _grant(
    '/refresh',
    {'refresh_token': refreshToken, 'device_id': deviceId},
  );

  Future<void> logout(String refreshToken, String deviceId) async {
    await _post('/logout', {
      'refresh_token': refreshToken,
      'device_id': deviceId,
    }, const Duration(seconds: 5));
  }

  Future<SessionGrant> _grant(String path, Map<String, String> body) async {
    final response = await _post(path, body, const Duration(seconds: 15));
    final data = _json(response.body);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SessionRejected(data['detail'] as String? ?? '登录已过期，请重新登录');
    }
    final token = data['token'];
    final refresh = data['refresh_token'];
    if (response.statusCode != 200 || token is! String || refresh is! String) {
      throw SessionUnavailable(data['message'] as String? ?? '服务暂不可用，请稍后重试');
    }
    final user = data['user'];
    final seconds = (data['expires_in'] as num?)?.toInt() ?? 3600;
    return SessionGrant(
      token: token,
      refreshToken: refresh,
      expiresAt: DateTime.now().add(Duration(seconds: seconds)),
      username: user is Map ? user['username'] as String? : null,
      nickname: user is Map ? user['nickname'] as String? : null,
    );
  }

  Future<http.Response> _post(
    String path,
    Map<String, String> body,
    Duration timeout,
  ) async {
    final client = _clientFactory();
    try {
      return await client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw SessionUnavailable('网络错误，请检查网络后重试');
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _json(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }
}
