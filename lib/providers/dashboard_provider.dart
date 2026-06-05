import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = buildDio();
  final results = await Future.wait([
    dio.get('/calls', queryParameters: {'per_page': 5, 'sort': 'desc'}),
    dio.get('/appointments', queryParameters: {'scope': 'week'}),
    dio.get('/contacts', queryParameters: {'per_page': 1}),
    dio.get('/assistants'),
  ]);

  final calls        = results[0].data;
  final appointments = results[1].data;
  final contacts     = results[2].data;
  final assistants   = results[3].data;

  final callList = (calls['data'] as List?) ?? [];
  final today    = DateTime.now();

  final callsToday = callList.where((c) {
    try {
      final d = DateTime.parse(c['started_at'] as String);
      return d.year == today.year && d.month == today.month && d.day == today.day;
    } catch (_) {
      return false;
    }
  }).length;

  return {
    'calls_today':       callsToday,
    'appointments_week': (appointments['data'] as List?)?.length ?? 0,
    'total_contacts':    contacts['meta']?['total'] ?? 0,
    'assistant_active':  (assistants['data'] as List?)?.isNotEmpty ?? false,
    'recent_calls':      callList.take(5).toList(),
  };
});
