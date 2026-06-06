import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple JSON + bool cache backed by SharedPreferences.
/// Bump [_version] whenever the data schema or logic changes to auto-invalidate old caches.
class AppCache {
  static const int _version = 3;
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _p() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static String _k(String key) => 'v${_version}_cache_$key';

  static Future<void> saveJson(String key, dynamic value) async {
    try {
      await (await _p()).setString(_k(key), jsonEncode(value));
    } catch (_) {}
  }

  static Future<dynamic> loadJson(String key) async {
    final s = (await _p()).getString(_k(key));
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveBool(String key, bool value) async {
    await (await _p()).setBool(_k(key), value);
  }

  static Future<bool?> loadBool(String key) async {
    return (await _p()).getBool(_k(key));
  }

  static Future<void> remove(String key) async {
    await (await _p()).remove(_k(key));
  }
}
