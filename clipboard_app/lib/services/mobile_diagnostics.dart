import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

enum MobileEvent {
  initialized,
  initializationFailed,
  accountConfigUnavailable,
  autoSynced,
  autoSyncFailed,
  historyFailed,
  readFailed,
}

/// Only fixed event names leave the device: never content, identity or exceptions.
class MobileDiagnostics {
  MobileDiagnostics({
    required this.endpoint,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? (() => http.Client());
  final String endpoint;
  final http.Client Function() _clientFactory;
  final String sessionId =
      'sc_${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
  final Map<MobileEvent, DateTime> _last = {};
  http.Client? _client;
  bool _disposed = false;
  bool _paused = false;
  bool _busy = false;
  Future<void> report(MobileEvent event) async {
    if (_disposed || _paused || _busy || endpoint.isEmpty) return;
    final now = DateTime.now();
    if (_last[event] != null && now.difference(_last[event]!).inSeconds < 30) {
      return;
    }
    _last[event] = now;
    _busy = true;
    final client = _clientFactory();
    _client = client;
    try {
      await client
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'source': 'shared-clipboard-mobile',
              'sessionId': sessionId,
              'message': event.name,
              'level':
                  event.name.endsWith('Failed') ||
                      event == MobileEvent.accountConfigUnavailable
                  ? 'warn'
                  : 'info',
              'type': 'custom',
              'page': '/clipboard',
              'appVersion': '1.1.1',
              'clientTime': now.millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      /* Reporting never blocks or retries the clipboard operation. */
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
      _busy = false;
    }
  }

  void pause() {
    _paused = true;
    _client?.close();
  }

  void resume() {
    if (!_disposed) _paused = false;
  }

  void dispose() {
    _disposed = true;
    pause();
    _last.clear();
  }
}
