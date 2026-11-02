import 'package:shared_preferences/shared_preferences.dart';

/// Stable per-install device id; the login session is bound to it.
class DeviceIdentity {
  static const prefsKey = 'clipboard_device_id';

  static String of(SharedPreferences prefs) {
    final existing = prefs.getString(prefsKey);
    if (existing != null) return existing;
    final now = DateTime.now();
    final created =
        'mobile-${now.millisecondsSinceEpoch}-${now.microsecond.toRadixString(36)}';
    prefs.setString(prefsKey, created);
    return created;
  }
}
