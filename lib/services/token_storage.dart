import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tries iOS Keychain first; falls back to SharedPreferences when the
/// Keychain is unavailable (simulator without entitlements, -34018 error).
class TokenStorage {
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'synovox_auth_token',
    ),
  );
  static const _secureKey = 'auth_token';
  static const _prefKey = 'synovox_auth_token_v1';

  static Future<String?> read() async {
    try {
      final t = await _secure.read(key: _secureKey);
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {}
    // Keychain failed — read from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  static Future<void> write(String token) async {
    // Write to both so whichever is readable later will work
    try {
      await _secure.write(key: _secureKey, value: token);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, token);
  }

  static Future<void> delete() async {
    try {
      await _secure.delete(key: _secureKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
}
