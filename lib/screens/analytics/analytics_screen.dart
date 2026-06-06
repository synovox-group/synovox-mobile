import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';

// ── Deep recursive metric finder ───────────────────────────────────────────────
// Searches any depth of nested maps for a numeric value matching any keyword.
int _deepFind(dynamic data, List<String> keywords, {int depth = 0}) {
  if (depth > 5) return 0;
  if (data is int) return data;
  if (data is double) return data.toInt();
  if (data is String) return int.tryParse(data) ?? 0;
  if (data is Map) {
    // 1. Exact key match
    for (final kw in keywords) {
      final v = data[kw];
      if (v != null) {
        if (v is int) return v;
        if (v is double) return v.toInt();
        if (v is String) { final n = int.tryParse(v); if (n != null) return n; }
        if (v is List) return v.length;
      }
    }
    // 2. Partial key match (avoid date/time fields)
    for (final entry in (data as Map).entries) {
      final k = entry.key.toString().toLowerCase();
      if (k.contains('_at') || k.contains('date') || k.contains('time') || k.contains('uuid')) continue;
      for (final kw in keywords) {
        if (k.contains(kw) || kw.contains(k)) {
          final v = entry.value;
          if (v is int) return v;
          if (v is double) return v.toInt();
          if (v is String) { final n = int.tryParse(v); if (n != null) return n; }
          if (v is List) return v.length;
        }
      }
    }
    // 3. Recurse into nested maps
    for (final v in (data as Map).values) {
      if (v is Map || v is List) {
        final found = _deepFind(v, keywords, depth: depth + 1);
        if (found > 0) return found;
      }
    }
  }
  if (data is List) return data.length;
  return 0;
}

Map<String, dynamic> _unwrap(dynamic raw) {
  if (raw is Map) {
    final d = raw['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    final s = raw['stats'];
    if (s is Map<String, dynamic>) return s;
    if (s is Map) return Map<String, dynamic>.from(s);
    return Map<String, dynamic>.from(raw);
  }
  if (raw is List) return {'_list': raw, 'total': raw.length};
  return {};
}

String _dateParam(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ── Providers ──────────────────────────────────────────────────────────────────

final analyticsCallsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 30));
  final res = await buildDio().get('/analytics/calls', queryParameters: {
    'start_date': _dateParam(start),
    'end_date': _dateParam(now),
    'period': 'month',
  });
  return _unwrap(res.data);
});

final analyticsPeakProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 30));
  final res = await buildDio().get('/analytics/peak-hours', queryParameters: {
    'start_date': _dateParam(start),
    'end_date': _dateParam(now),
  });
  return _unwrap(res.data);
});

final analyticsApptsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 30));
  final res = await buildDio().get('/analytics/appointments', queryParameters: {
    'start_date': _dateParam(start),
    'end_date': _dateParam(now),
    'period': 'month',
  });
  return _unwrap(res.data);
});

// ── Main screen ────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(analyticsCallsProvider);
    final peak = ref.watch(analyticsPeakProvider);
    final appts = ref.watch(analyticsApptsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytiques'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(analyticsCallsProvider);
              ref.invalidate(analyticsPeakProvider);
              ref.invalidate(analyticsApptsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyticsCallsProvider);
          ref.invalidate(analyticsPeakProvider);
          ref.invalidate(analyticsApptsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(children: [
                const Icon(Icons.date_range_rounded,
                    size: 14, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(
                  '30 derniers jours — ${_dateParam(DateTime.now().subtract(const Duration(days: 30)))} → ${_dateParam(DateTime.now())}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF1E40AF)),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Appels ────────────────────────────────────────
            _SectionHeader(
                title: 'Appels',
                icon: Icons.phone_in_talk_rounded,
                color: const Color(0xFF2563EB)),
            const SizedBox(height: 10),
            calls.when(
              loading: () => const _StatsSkeleton(),
              error: (e, __) => _ErrorCard(e: e, onRetry: () => ref.invalidate(analyticsCallsProvider)),
              data: (data) => _CallsStats(data: data),
            ),
            const SizedBox(height: 20),

            // ── Heures de pointe ──────────────────────────────
            _SectionHeader(
                title: 'Heures de pointe',
                icon: Icons.bar_chart_rounded,
                color: const Color(0xFF7C3AED)),
            const SizedBox(height: 10),
            peak.when(
              loading: () => const _StatsSkeleton(height: 160),
              error: (e, __) => _ErrorCard(e: e, onRetry: () => ref.invalidate(analyticsPeakProvider)),
              data: (data) => _PeakHoursChart(data: data),
            ),
            const SizedBox(height: 20),

            // ── Rendez-vous ───────────────────────────────────
            _SectionHeader(
                title: 'Rendez-vous',
                icon: Icons.calendar_today_rounded,
                color: const Color(0xFF059669)),
            const SizedBox(height: 10),
            appts.when(
              loading: () => const _StatsSkeleton(),
              error: (e, __) => _ErrorCard(e: e, onRetry: () => ref.invalidate(analyticsApptsProvider)),
              data: (data) => _ApptsStats(data: data),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Calls Stats ────────────────────────────────────────────────────────────────

class _CallsStats extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CallsStats({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = _deepFind(data,
        ['total', 'total_calls', 'calls_total', 'count', 'calls_count', 'all', 'calls']);
    final completed = _deepFind(data,
        ['completed', 'answered', 'completed_calls', 'handled', 'success']);
    final missed = _deepFind(data,
        ['missed', 'unanswered', 'missed_calls', 'no_answer', 'failed', 'voicemail']);
    final avgDur = _deepFind(data,
        ['avg_duration', 'average_duration', 'avg_duration_seconds',
         'average_call_duration', 'duration_avg', 'mean_duration']);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _StatCard(
            label: 'Total appels',
            value: '$total',
            icon: Icons.phone_rounded,
            color: const Color(0xFF2563EB)),
        _StatCard(
            label: 'Traités',
            value: '$completed',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF059669)),
        _StatCard(
            label: 'Manqués',
            value: '$missed',
            icon: Icons.phone_missed_rounded,
            color: const Color(0xFFDC2626)),
        _StatCard(
            label: 'Durée moy.',
            value: _fmtDur(avgDur),
            icon: Icons.timer_rounded,
            color: const Color(0xFF7C3AED)),
      ],
    );
  }

  String _fmtDur(int s) {
    if (s == 0) return '—';
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m${(s % 60).toString().padLeft(2, '0')}s';
  }
}

// ── Peak Hours Chart ───────────────────────────────────────────────────────────

class _PeakHoursChart extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PeakHoursChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final Map<int, int> hourCounts = {};

    // Try multiple data shapes
    dynamic hoursData = data['hours']
        ?? data['peak_hours']
        ?? data['by_hour']
        ?? data['hourly']
        ?? data['data']
        ?? data;

    if (hoursData is Map) {
      hoursData.forEach((k, v) {
        final h = int.tryParse('$k');
        final c = v is int ? v : (v is double ? v.toInt() : int.tryParse('$v') ?? 0);
        if (h != null) hourCounts[h] = c;
      });
    } else if (hoursData is List) {
      for (final item in hoursData) {
        if (item is Map) {
          final h = item['hour'] as int?
              ?? int.tryParse('${item['hour_of_day'] ?? item['h'] ?? ''}');
          final c = item['count'] as int?
              ?? item['calls'] as int?
              ?? item['total'] as int?
              ?? 0;
          if (h != null) hourCounts[h] = c;
        }
      }
    }

    if (hourCounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Text('Pas encore de données sur cette période',
              style: TextStyle(color: Color(0xFF94A3B8))),
        ),
      );
    }

    final maxVal = hourCounts.values.fold(0, (a, b) => a > b ? a : b);
    final peakHour =
        hourCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Appels par heure',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B))),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (h) {
              final count = hourCounts[h] ?? 0;
              final ratio = maxVal > 0 ? count / maxVal : 0.0;
              final isPeak = h == peakHour && count > 0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: ratio == 0 ? 0.02 : ratio,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isPeak
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFFDDD6FE),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (h % 6 == 0)
                        Text('$h',
                            style: const TextStyle(
                                fontSize: 8, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        if (maxVal > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(2),
                )),
            const SizedBox(width: 6),
            Text(
              'Pic : ${peakHour}h00 ($maxVal appels)',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF64748B)),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ── Appointments Stats ─────────────────────────────────────────────────────────

class _ApptsStats extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ApptsStats({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = _deepFind(data,
        ['total', 'total_appointments', 'appointments_total', 'count', 'appointments_count', 'appointments']);
    final confirmed = _deepFind(data,
        ['confirmed', 'confirmed_count', 'accepted', 'booked']);
    final pending = _deepFind(data,
        ['pending', 'scheduled', 'pending_count', 'planned', 'upcoming']);
    final cancelled = _deepFind(data,
        ['cancelled', 'canceled', 'cancelled_count', 'rejected', 'refused']);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _StatCard(
            label: 'Total RDV',
            value: '$total',
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFF059669)),
        _StatCard(
            label: 'Confirmés',
            value: '$confirmed',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF2563EB)),
        _StatCard(
            label: 'En attente',
            value: '$pending',
            icon: Icons.schedule_rounded,
            color: const Color(0xFFF59E0B)),
        _StatCard(
            label: 'Annulés',
            value: '$cancelled',
            icon: Icons.cancel_outlined,
            color: const Color(0xFFDC2626)),
      ],
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader(
      {required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600)),
      ]);
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF64748B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _StatsSkeleton extends StatelessWidget {
  final double height;
  const _StatsSkeleton({this.height = 110});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
}

class _ErrorCard extends StatelessWidget {
  final Object e;
  final VoidCallback onRetry;
  const _ErrorCard({required this.e, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFCDD2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFDC2626), size: 18),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Impossible de charger',
                    style: TextStyle(fontSize: 13))),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ]),
          SelectableText(e.toString(),
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF94A3B8))),
        ]),
      );
}
