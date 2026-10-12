import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/clipboard_item.dart';

/// 同步结果
class SyncResult {
  final List<ClipboardItem> items;
  final int total;
  final String syncedAt;

  SyncResult({
    required this.items,
    required this.total,
    required this.syncedAt,
  });
}

/// 剪贴板 HTTP API 客户端
///
/// 封装后端 5 个 REST API：history / add / sync / delete / clear。
/// 与桌面端 TypeScript 的 httpFetch 调用完全对齐。
class ClipboardApiClient {
  final ClipboardConfig config;
  final http.Client _client;

  ClipboardApiClient({required this.config, http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (config.token != null) 'Authorization': 'Bearer ${config.token}',
  };

  /// GET /clipboard/history - 获取剪贴板历史记录
  ///
  /// [limit] 最大返回条数，默认 200
  /// [days] 按天数筛选（可选）
  Future<List<ClipboardItem>> getHistory({
    int limit = 200,
    int? days,
    bool metadataOnly = false,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'metadata_only': metadataOnly.toString(),
    };
    if (days != null) params['days'] = days.toString();

    final uri = Uri.parse(
      '${config.apiBaseUrl}/clipboard/history',
    ).replace(queryParameters: params);

    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body['code'] == 1 || body['code'] == 200) {
      final list = body['data'] as List;
      return list
          .map((e) => ClipboardItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException(body['message'] as String? ?? '获取历史记录失败');
  }

  Future<ClipboardItem> getItem(String id) async {
    final response = await _client
        .get(
          Uri.parse(
            '${config.apiBaseUrl}/clipboard/item/${Uri.encodeComponent(id)}',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] == 1 || body['code'] == 200) {
      return ClipboardItem.fromJson(body['data'] as Map<String, dynamic>);
    }
    throw ApiException('读取内容失败');
  }

  /// POST /clipboard/add - 添加剪贴板记录
  ///
  /// 包含去重逻辑，服务端会自动清理超过 200 条的旧记录。
  Future<ClipboardItem> addItem({
    required String content,
    required String contentType,
    required String deviceId,
    String deviceName = '',
    String? preview,
    String? imageUrl,
    bool encrypted = false,
    String? contentHash,
  }) async {
    final uri = Uri.parse('${config.apiBaseUrl}/clipboard/add');
    final payload = {
      'content': content,
      'content_type': contentType,
      'device_id': deviceId,
      'device_name': deviceName,
      'preview': preview,
      'image_url': imageUrl,
      'encrypted': encrypted,
      'content_hash': contentHash,
    };

    final response = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode(payload),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body['code'] == 1 || body['code'] == 200) {
      return ClipboardItem.fromJson(body['data'] as Map<String, dynamic>);
    }

    throw ApiException(body['message'] as String? ?? '添加记录失败');
  }

  /// GET /clipboard/sync - 增量同步
  ///
  /// [since] ISO 8601 时间戳，返回此时间之后的新记录
  Future<SyncResult> sync({String? since}) async {
    final params = <String, String>{};
    if (since != null) params['since'] = since;

    final uri = Uri.parse(
      '${config.apiBaseUrl}/clipboard/sync',
    ).replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body['code'] == 1 || body['code'] == 200) {
      final data = body['data'] as Map<String, dynamic>;
      final items = (data['items'] as List)
          .map((e) => ClipboardItem.fromJson(e as Map<String, dynamic>))
          .toList();

      return SyncResult(
        items: items,
        total: data['total'] as int,
        syncedAt: data['syncedAt'] as String,
      );
    }

    throw ApiException(body['message'] as String? ?? '同步失败');
  }

  /// DELETE /clipboard/delete/{itemId} - 删除单条记录
  Future<void> deleteItem(String itemId) async {
    final uri = Uri.parse('${config.apiBaseUrl}/clipboard/delete/$itemId');
    final response = await _client.delete(uri, headers: _headers);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body['code'] != 1 && body['code'] != 200) {
      throw ApiException(body['message'] as String? ?? '删除失败');
    }
  }

  /// DELETE /clipboard/clear - 清空全部历史
  Future<void> clearHistory() async {
    final uri = Uri.parse('${config.apiBaseUrl}/clipboard/clear');
    final response = await _client.delete(uri, headers: _headers);
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body['code'] != 1 && body['code'] != 200) {
      throw ApiException(body['message'] as String? ?? '清空失败');
    }
  }

  /// 释放资源
  void dispose() {
    _client.close();
  }
}

/// API 异常
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
