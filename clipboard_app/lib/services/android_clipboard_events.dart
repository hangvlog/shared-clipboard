import 'package:flutter/services.dart';

/// Android sends change/focus events only. Clipboard bodies stay in the adapter.
class AndroidClipboardEvents {
  static const _channel = MethodChannel('chat.clawkit.clipboard/events');
  void start(void Function() changed) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') changed();
    });
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
