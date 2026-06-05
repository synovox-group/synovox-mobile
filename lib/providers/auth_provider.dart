import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_client.dart';

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

  final _storage = const FlutterSecureStorage();
  final _dio = buildDio();

  Future<void> _init() async {
    final token = await _storage.read(key: 'auth_token');
    if (token != null) {
      state = state.copyWith(token: token);
      await _fetchMe();
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(loading: true);
    try {
      final res = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final token = res.data['data']['token'] as String;
      await _storage.write(key: 'auth_token', value: token);
      state = state.copyWith(
        token: token,
        user: res.data['data']['user'] as Map<String, dynamic>,
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
      rethrow;
    }
  }

  Future<void> _fetchMe() async {
    try {
      final res = await _dio.get('/auth/me');
      state = state.copyWith(user: res.data['data'] as Map<String, dynamic>);
    } catch (_) {
      await logout();
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await _storage.delete(key: 'auth_token');
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
