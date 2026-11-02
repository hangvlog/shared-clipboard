import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/device_identity.dart';
import '../services/session_api.dart';

/// 认证状态管理
///
/// 登录得到 24 小时访问令牌和绑定本机的续期凭据；令牌临近过期或被拒绝时自动续期，
/// 只要定期打开应用，会话就一直有效。只有服务端明确拒绝续期（退出、撤销、长期未用）才回到登录页。
class AuthStore extends ChangeNotifier {
  AuthStore({SessionApi? api}) : _api = api ?? SessionApi() {
    _ready = _loadSavedToken();
  }

  static const renewBefore = Duration(hours: 2);

  final SessionApi _api;
  late final Future<void> _ready;
  Future<bool>? _renewing;
  String? _token;
  String? _refreshToken;
  int _expiresAt = 0;
  String? _deviceId;
  String? _username;
  String? _nickname;
  bool _isLoading = false;
  String? _sessionNotice;
  String? _lastLogin;

  String? get token => _token;
  String? get sessionNotice => _sessionNotice;
  String? get lastLogin => _lastLogin;
  String? get username => _username;
  String? get nickname => _nickname;
  bool get isLoggedIn => _token != null;
  bool get isLoading => _isLoading;
  bool get canRenew => _refreshToken != null;

  /// 从本地存储恢复登录状态
  Future<void> _loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = DeviceIdentity.of(prefs);
    _token = prefs.getString('auth_token');
    _refreshToken = prefs.getString('auth_refresh_token');
    _expiresAt = prefs.getInt('auth_expires_at') ?? 0;
    _username = prefs.getString('auth_username');
    _nickname = prefs.getString('auth_nickname');
    _lastLogin = prefs.getString('auth_last_login');
    if (_token != null || _lastLogin != null) {
      notifyListeners();
    }
    unawaited(ensureFresh());
  }

  /// 登录：POST /codex-remote/sso/password（client=shared-clipboard）
  Future<String?> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _ready;
      final grant = await _api.login(username, password, _deviceId!);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_last_login', username);
      _lastLogin = username;
      _sessionNotice = null;
      await _apply(grant, fallbackName: username);
      return null;
    } on SessionRejected catch (e) {
      return e.message;
    } on SessionUnavailable catch (e) {
      return e.message;
    } catch (_) {
      return '登录失败，请稍后重试';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Renew ahead of expiry; cheap no-op while the access token is fresh.
  Future<void> ensureFresh() async {
    await _ready;
    if (_token == null || _refreshToken == null) return;
    final renewAt = _expiresAt - renewBefore.inMilliseconds;
    if (DateTime.now().millisecondsSinceEpoch < renewAt) return;
    await renew();
  }

  /// Returns true when a new access token was issued. Concurrent callers share one request.
  Future<bool> renew() => _renewing ??= _renew().whenComplete(() {
    _renewing = null;
  });

  Future<bool> _renew() async {
    await _ready;
    final refresh = _refreshToken;
    if (_token == null) return false;
    if (refresh == null) {
      await expireSession();
      return false;
    }
    try {
      final grant = await _api.refresh(refresh, _deviceId!);
      if (_refreshToken != refresh) return false;
      await _apply(grant);
      return true;
    } on SessionRejected {
      if (_refreshToken == refresh) await expireSession();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _apply(SessionGrant grant, {String? fallbackName}) async {
    _token = grant.token;
    _refreshToken = grant.refreshToken;
    _expiresAt = grant.expiresAt.millisecondsSinceEpoch;
    _username = grant.username ?? _username ?? fallbackName;
    _nickname = grant.nickname ?? _nickname ?? _username;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', grant.token);
    await prefs.setString('auth_refresh_token', grant.refreshToken);
    await prefs.setInt('auth_expires_at', _expiresAt);
    if (_username != null) await prefs.setString('auth_username', _username!);
    if (_nickname != null) await prefs.setString('auth_nickname', _nickname!);
    notifyListeners();
  }

  /// The server rejected the session; return to login and keep the account name.
  Future<void> expireSession() async {
    if (_token == null) return;
    await _signOut('登录已过期，请重新登录');
  }

  /// 登出：同时撤销服务端的续期凭据
  Future<void> logout() async {
    final refresh = _refreshToken;
    final deviceId = _deviceId;
    await _signOut(null);
    if (refresh != null && deviceId != null) {
      unawaited(_api.logout(refresh, deviceId).catchError((Object _) {}));
    }
  }

  Future<void> _signOut(String? notice) async {
    _sessionNotice = notice;
    _token = null;
    _refreshToken = null;
    _expiresAt = 0;
    _username = null;
    _nickname = null;

    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'auth_token',
      'auth_refresh_token',
      'auth_expires_at',
      'auth_username',
      'auth_nickname',
    ]) {
      await prefs.remove(key);
    }

    notifyListeners();
  }
}
