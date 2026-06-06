import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../utils/tz.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = buildDio();

  // Fetch everything in parallel — overview for stats, calls/appointments for lists
  Map<String, dynamic> overview = {};
  List recentCalls = [];
  int appointmentsWeek = 0;
  int totalContacts = 0;
  bool assistantActive = false;
  String assistantName = '';

  await Future.wait([
    // Overview stats
    dio.get('/dashboard/overview').then((r) {
      overview = r.data['data'] as Map<String, dynamic>?
          ?? r.data as Map<String, dynamic>?
          ?? {};
    }).catchError((_) {}),

    // Recent calls — always fetch directly so we always have them
    dio.get('/calls', queryParameters: {
      'per_page': 5,
      'sort': 'desc',
      'order_by': 'created_at',
    }).then((r) {
      final raw = r.data;
      if (raw is Map) {
        recentCalls = (raw['data'] as List?)
            ?? (raw['calls'] as List?)
            ?? [];
      } else if (raw is List) {
        recentCalls = raw;
      }
    }).catchError((_) {}),

    // Appointments this week
    dio.get('/appointments', queryParameters: {'scope': 'week'}).then((r) {
      appointmentsWeek = _safeList(r.data).length;
    }).catchError((_) {}),

    // Contacts count
    dio.get('/contacts', queryParameters: {'per_page': 1}).then((r) {
      final raw = r.data;
      if (raw is Map) {
        totalContacts = raw['meta']?['total'] as int?
            ?? raw['meta']?['count'] as int?
            ?? _safeList(raw).length;
      }
    }).catchError((_) {}),

    // Assistants — check first one configured
    dio.get('/assistants').then((r) {
      final list = _safeList(r.data);
      if (list.isEmpty) return;
      final first = list.first;
      if (first is! Map) { assistantActive = true; return; }
      // Grab name
      assistantName = first['name'] as String?
          ?? first['assistant_name'] as String?
          ?? '';
      // Determine active status
      final active = first['is_active'] ?? first['active'] ?? first['status'];
      if (active is bool) {
        assistantActive = active;
      } else if (active is int) {
        assistantActive = active != 0;
      } else if (active is String) {
        assistantActive = active == 'active' || active == 'enabled'
            || active == 'true' || active == '1' || active == 'on';
      } else {
        assistantActive = true; // present but no explicit status → consider active
      }
    }).catchError((_) {}),
  ]);

  // Calculate calls today from the list (Europe/Zurich)
  final today = utcToZurich(DateTime.now().toUtc());
  final callsToday = recentCalls.where((c) {
    final d = parseZurich(
        c['started_at'] as String? ?? c['start_time'] as String?);
    if (d == null) return false;
    return d.year == today.year &&
        d.month == today.month &&
        d.day == today.day;
  }).length;

  // Merge overview stats (if returned) with our calculated values
  return {
    'calls_today': _num(overview, ['calls_today', 'total_calls_today',
        'today_calls', 'calls_count']) ?? callsToday,
    'appointments_week': _num(overview, ['appointments_week',
        'week_appointments', 'appointments_this_week',
        'upcoming_appointments_count']) ?? appointmentsWeek,
    'total_contacts': _num(overview, ['total_contacts', 'contacts_count',
        'contacts_total', 'contacts']) ?? totalContacts,
    'assistant_active': _bool(overview, ['assistant_active',
        'has_active_assistant', 'active_assistant']) ?? assistantActive,
    'assistant_name': assistantName,
    'recent_calls': recentCalls.take(5).toList(),
    'upcoming_appointments': (overview['upcoming_appointments'] as List?)
        ?? (overview['next_appointments'] as List?)
        ?? [],
  };
});

/// Safely extract a List from any API response shape.
/// Handles: List root, {data: [...]}, {data: {...}}, {items: [...]}, etc.
List _safeList(dynamic raw) {
  if (raw is List) return raw;
  if (raw is Map) {
    for (final key in ['data', 'items', 'results', 'list', 'records']) {
      final v = raw[key];
      if (v is List) return v;
      if (v is Map) return [v]; // single item wrapped in object
    }
    // root itself is a single object (no wrapper)
    if (raw.isNotEmpty) return [raw];
  }
  return [];
}

int? _num(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
  }
  return null;
}

bool? _bool(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is bool) return v;
  }
  return null;
}
