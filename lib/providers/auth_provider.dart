import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../services/token_storage.dart';

class AuthState {
  final String? token;
  final Map<String, dynamic>? user;
  final bool loading;

  const AuthState({this.token, this.user, this.loading = false});

  AuthState copyWith({String? token, Map<String, dynamic>? user, bool? loading}) =>
      AuthState(
        token: token ?? this.token,
        user: user ?? this.user,
        loading: loading ?? this.loading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  final _dio = buildDio();

  // ── Startup: restore session from storage ──────────────────────────────
  Future<void> _init() async {
    try {
      final token = await TokenStorage.read();
      if (token != null && token.isNotEmpty) {
        state = state.copyWith(token: token);
        await _fetchMe();
      }
    } catch (_) {}
  }

  // ── Login ──────────────────────────────────────────────────────────────
  Future<void> login(String email, String password) async {
    state = state.copyWith(loading: true);
    try {
      final res = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      debugPrint('[Auth] login response: ${res.data}');

      final body = res.data;
      String? token;
      Map<String, dynamic>? userData;

      if (body is Map) {
        // Support {data: {token:...}} and flat {token:...}
        final inner = body['data'] is Map ? body['data'] as Map : body;
        token = _str(inner['token']) ?? _str(inner['access_token'])
            ?? _str(body['token']) ?? _str(body['access_token']);
        final u = inner['user'] ?? body['user'];
        if (u is Map) userData = Map<String, dynamic>.from(u);
      }

      debugPrint('[Auth] token extracted: ${token != null ? "OK (${token.length} chars)" : "NULL"}');

      if (token == null || token.isEmpty) {
        throw Exception('Token introuvable dans la réponse du serveur.');
      }

      // Persist — uses Keychain + SharedPreferences fallback
      await TokenStorage.write(token);
      state = state.copyWith(token: token, user: userData, loading: false);
    } catch (e) {
      debugPrint('[Auth] login error: $e');
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  // ── Fetch profile ──────────────────────────────────────────────────────
  Future<void> _fetchMe() async {
    if (state.loading) return;
    try {
      final res = await _dio.get('/auth/me');
      _applyUserFromResponse(res.data);
    } on Object catch (e) {
      // Only clear session on 401 — not on network errors
      final is401 = e.toString().contains('401');
      if (is401) await logout();
    }
  }

  Future<void> refreshProfile() async {
    try {
      final res = await _dio.get('/auth/me');
      _applyUserFromResponse(res.data);
    } catch (_) {}
  }

  void _applyUserFromResponse(dynamic body) {
    if (body is! Map) return;
    final inner = body['data'] is Map ? body['data'] as Map : body;
    if (inner is Map && mounted) {
      state = state.copyWith(user: Map<String, dynamic>.from(inner));
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await TokenStorage.delete();
    if (mounted) state = const AuthState();
  }
}

String? _str(dynamic v) =>
    (v is String && v.isNotEmpty) ? v : null;

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
