import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/env_config.dart';

/// 认证状态管理
///
/// 对应桌面端 authStore.ts，负责登录、登出、Token 持久化。
class AuthStore extends ChangeNotifier {
  String? _token;
  String? _username;
  String? _nickname;
  bool _isLoading = false;

  String? get token => _token;
  String? get username => _username;
  String? get nickname => _nickname;
  bool get isLoggedIn => _token != null;
  bool get isLoading => _isLoading;

  AuthStore() {
    _loadSavedToken();
  }

  /// 从本地存储恢复登录状态
  Future<void> _loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _username = prefs.getString('auth_username');
    _nickname = prefs.getString('auth_nickname');
    if (_token != null) {
      notifyListeners();
    }
  }

  /// 登录
  ///
  /// 调用后端 POST /auth/login 接口
  Future<String?> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final uri = Uri.parse('${EnvConfig.apiBaseUrl}/auth/login');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 1 || body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>;
        _token = data['token'] as String?;
        final userInfo = data['user'] as Map<String, dynamic>?;
        _username = userInfo?['username'] as String? ?? username;
        _nickname = userInfo?['nickname'] as String? ?? username;

        // 持久化
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await prefs.setString('auth_username', _username!);
        await prefs.setString('auth_nickname', _nickname!);

        notifyListeners();
        return null; // 成功
      }

      return body['message'] as String? ?? '登录失败';
    } catch (e) {
      return '网络错误: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 登出
  Future<void> logout() async {
    _token = null;
    _username = null;
    _nickname = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
    await prefs.remove('auth_nickname');

    notifyListeners();
  }
}
