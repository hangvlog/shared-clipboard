import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env_config.dart';

/// One installable package from `GET /api/releases/shared-clipboard/update`.
class AppUpdate {
  AppUpdate({
    required this.hasUpdate,
    required this.mandatory,
    this.version,
    this.notes = const [],
    this.url,
    this.sha256,
    this.size,
  });

  final bool hasUpdate;
  final bool mandatory;
  final String? version;
  final List<String> notes;
  final String? url;
  final String? sha256;
  final int? size;

  factory AppUpdate.fromJson(Map<String, dynamic> data) {
    final latest = data['latest'];
    final artifact = data['artifact'];
    return AppUpdate(
      hasUpdate: data['has_update'] == true,
      mandatory: data['mandatory'] == true,
      version: latest is Map ? latest['version'] as String? : null,
      notes: latest is Map && latest['notes'] is List
          ? (latest['notes'] as List).whereType<String>().toList()
          : const [],
      url: artifact is Map ? artifact['url'] as String? : null,
      sha256: artifact is Map ? artifact['sha256'] as String? : null,
      size: artifact is Map ? (artifact['size'] as num?)?.toInt() : null,
    );
  }

  /// Refuse anything the native verifier would reject, before starting a download.
  void validateInstallable() {
    final uri = Uri.tryParse(url ?? '');
    if (!hasUpdate ||
        version == null ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version!)) {
      throw StateError('没有可安装的更新');
    }
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw StateError('更新只允许安全下载地址');
    }
    final bytes = size ?? 0;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256 ?? '') ||
        bytes <= 0 ||
        bytes > 200 * 1024 * 1024) {
      throw StateError('安装包缺少有效校验信息，请稍后检查更新');
    }
  }
}

/// Platform-aware check: compares the Android package this client would install.
class AppUpdateApi {
  AppUpdateApi({String? baseUrl, http.Client Function()? clientFactory})
    : _baseUrl = baseUrl ?? EnvConfig.apiBaseUrl,
      _clientFactory = clientFactory ?? http.Client.new;
  final String _baseUrl;
  final http.Client Function() _clientFactory;

  Future<AppUpdate> check(String currentVersion) async {
    final uri = Uri.parse('$_baseUrl/releases/shared-clipboard/update').replace(
      queryParameters: {
        'current_version': currentVersion,
        'platform': 'android',
        'arch': 'universal',
        'channel': 'preview',
      },
    );
    final client = _clientFactory();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('更新服务暂不可用（${response.statusCode}）');
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map || body['code'] != 200 || body['data'] is! Map) {
        throw StateError('检查更新失败');
      }
      return AppUpdate.fromJson(Map<String, dynamic>.from(body['data']));
    } finally {
      client.close();
    }
  }
}
