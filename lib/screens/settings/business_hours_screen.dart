import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../services/app_cache.dart';

class _BusinessHoursNotifier extends AsyncNotifier<Map<String, dynamic>> {
  static const _key = 'business_hours';

  @override
  Future<Map<String, dynamic>> build() async {
    final cached = await AppCache.loadJson(_key);
    if (cached is Map && cached.isNotEmpty) {
      Future.microtask(_backgroundRefresh);
      return Map<String, dynamic>.from(cached);
    }
    return _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final res = await buildDio().get('/business-hours');
    final data = _normalise(res.data);
    await AppCache.saveJson(_key, data);
    return data;
  }

  Future<void> _backgroundRefresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (_) {}
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Save updated hours to API and cache.
  Future<void> save(Map<String, Map<String, dynamic>> hours) async {
    await buildDio().put('/business-hours', data: hours);
    final updated = Map<String, dynamic>.from(hours);
    await AppCache.saveJson(_key, updated);
    state = AsyncData(updated);
  }

  /// API returns: {data: [{day_of_week: 0..6, opens_at, closes_at, is_closed}, ...]}
  /// day_of_week: 0=Sunday, 1=Monday ... 6=Saturday
  static Map<String, dynamic> _normalise(dynamic raw) {
    dynamic inner = raw;
    if (inner is Map) {
      inner = inner['data'] ?? inner['business_hours'] ?? inner['hours'] ?? inner;
    }
    if (inner is List) {
      const dow = ['sunday','monday','tuesday','wednesday','thursday','friday','saturday'];
      final map = <String, dynamic>{};
      for (final item in inner) {
        if (item is! Map) continue;
        // day_of_week: 0=Sun, 1=Mon ... 6=Sat
        final dowInt = item['day_of_week'];
        if (dowInt is int && dowInt >= 0 && dowInt < 7) {
          map[dow[dowInt]] = {
            'id': item['id'],
            'is_open': !(item['is_closed'] as bool? ?? true),
            'open_time': item['opens_at']?.toString() ?? '08:00',
            'close_time': item['closes_at']?.toString() ?? '18:00',
          };
          continue;
        }
        // Fallback: try named day field
        final day = item['day']?.toString()
            ?? item['weekday']?.toString()
            ?? item['name']?.toString();
        if (day != null) {
          map[day.toLowerCase()] = item;
        }
      }
      if (map.isNotEmpty) return map;
    }
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return {};
  }
}

final businessHoursProvider =
    AsyncNotifierProvider<_BusinessHoursNotifier, Map<String, dynamic>>(
        _BusinessHoursNotifier.new);

const _days = [
  ('monday',    'Lundi'),
  ('tuesday',   'Mardi'),
  ('wednesday', 'Mercredi'),
  ('thursday',  'Jeudi'),
  ('friday',    'Vendredi'),
  ('saturday',  'Samedi'),
  ('sunday',    'Dimanche'),
];

class BusinessHoursScreen extends ConsumerStatefulWidget {
  const BusinessHoursScreen({super.key});

  @override
  ConsumerState<BusinessHoursScreen> createState() => _BusinessHoursScreenState();
}

class _BusinessHoursScreenState extends ConsumerState<BusinessHoursScreen> {
  // Local editable state: day → {is_open, open_time, close_time}
  Map<String, Map<String, dynamic>> _hours = {};
  bool _dirty = false;
  bool _saving = false;

  void _initFrom(Map<String, dynamic> data) {
    _hours = {};
    for (final (key, _) in _days) {
      final d = data[key] as Map? ?? {};
      _hours[key] = {
        'is_open': _safeBool(d['is_open'] ?? d['open'] ?? d['enabled'] ?? d['active']),
        'open_time': _safeTime(
            d['open_time'] ?? d['start_time'] ?? d['opens_at'] ?? d['opening_time'],
            fallback: '08:00'),
        'close_time': _safeTime(
            d['close_time'] ?? d['end_time'] ?? d['closes_at'] ?? d['closing_time'],
            fallback: '18:00'),
      };
    }
  }

  static bool _safeBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return false;
  }

  static String _safeTime(dynamic v, {required String fallback}) {
    if (v == null) return fallback;
    if (v is String && v.isNotEmpty) {
      // "08:00:00" → "08:00"
      if (v.contains(':')) return v.substring(0, 5);
      return v;
    }
    if (v is int) {
      // Could be hour (8), HHMM (800), or seconds (28800)
      if (v < 24) return '${v.toString().padLeft(2, '0')}:00';
      if (v < 10000) {
        final h = v ~/ 100;
        final m = v % 100;
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
      // seconds since midnight
      final h = v ~/ 3600;
      final m = (v % 3600) ~/ 60;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(businessHoursProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horaires d\'ouverture'),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _error(e, () => ref.read(businessHoursProvider.notifier).refresh()),
        data: (data) {
          if (_hours.isEmpty || !_dirty) _initFrom(data);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Définissez quand votre assistant prend les appels.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              ..._days.map((d) => _DayRow(
                dayKey: d.$1,
                dayLabel: d.$2,
                isOpen: _hours[d.$1]?['is_open'] as bool? ?? false,
                openTime: _hours[d.$1]?['open_time'] as String? ?? '08:00',
                closeTime: _hours[d.$1]?['close_time'] as String? ?? '18:00',
                onChanged: (key, val) {
                  setState(() {
                    _hours[d.$1]![key] = val;
                    _dirty = true;
                  });
                },
                onPickTime: (key) => _pickTime(d.$1, key),
              )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickTime(String dayKey, String timeKey) async {
    final current = _hours[dayKey]?[timeKey] as String? ?? '08:00';
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts[1]) ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _hours[dayKey]![timeKey] =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(businessHoursProvider.notifier).save(_hours);
      setState(() => _dirty = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horaires enregistrés')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _error(Object e, VoidCallback onRetry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('Impossible de charger les horaires',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            SelectableText(
              e.toString(),
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ]),
        ),
      );
}

class _DayRow extends StatelessWidget {
  final String dayKey, dayLabel, openTime, closeTime;
  final bool isOpen;
  final void Function(String key, dynamic val) onChanged;
  final void Function(String timeKey) onPickTime;

  const _DayRow({
    required this.dayKey,
    required this.dayLabel,
    required this.isOpen,
    required this.openTime,
    required this.closeTime,
    required this.onChanged,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SizedBox(
                width: 90,
                child: Text(dayLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              const Spacer(),
              Text(isOpen ? 'Ouvert' : 'Fermé',
                  style: TextStyle(
                      fontSize: 12,
                      color: isOpen
                          ? const Color(0xFF059669)
                          : const Color(0xFF94A3B8))),
              const SizedBox(width: 8),
              Switch(
                value: isOpen,
                onChanged: (v) => onChanged('is_open', v),
                activeColor: const Color(0xFF059669),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),
            if (isOpen) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _TimeButton(
                    label: 'Ouverture',
                    time: openTime,
                    onTap: () => onPickTime('open_time'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child:
                      Text('→', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                Expanded(
                  child: _TimeButton(
                    label: 'Fermeture',
                    time: closeTime,
                    onTap: () => onPickTime('close_time'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label, time;
  final VoidCallback onTap;
  const _TimeButton({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF94A3B8))),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.access_time_rounded,
                    size: 14, color: Color(0xFF2563EB)),
                const SizedBox(width: 4),
                Text(time,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
            ],
          ),
        ),
      );
}
