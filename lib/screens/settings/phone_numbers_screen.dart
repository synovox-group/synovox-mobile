import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../services/app_cache.dart';

class _PhoneNumbersNotifier extends AsyncNotifier<List> {
  static const _key = 'phone_numbers';

  @override
  Future<List> build() async {
    final cached = await AppCache.loadJson(_key);
    if (cached is List && cached.isNotEmpty) {
      Future.microtask(_backgroundRefresh);
      return List.from(cached);
    }
    return _fetch();
  }

  Future<List> _fetch() async {
    final res = await buildDio().get('/phone-numbers');
    final data = _safeListP(res.data);
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
}

final phoneNumbersProvider =
    AsyncNotifierProvider<_PhoneNumbersNotifier, List>(
        _PhoneNumbersNotifier.new);

bool? _safeBoolP(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true' || v == 'active';
  return null;
}

List _safeListP(dynamic raw) {
  if (raw is List) return raw;
  if (raw is Map) {
    for (final key in ['data', 'phone_numbers', 'numbers', 'items', 'results']) {
      final v = raw[key];
      if (v is List) return v;
      if (v is Map) return [v];
    }
    if ((raw as Map).isNotEmpty) return [raw];
  }
  return [];
}

class PhoneNumbersScreen extends ConsumerWidget {
  const PhoneNumbersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(phoneNumbersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Numéros de téléphone'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(phoneNumbersProvider.notifier).refresh(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(e: e, onRetry: () => ref.read(phoneNumbersProvider.notifier).refresh()),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.phone_outlined, size: 52, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text('Aucun numéro configuré',
                    style: TextStyle(color: Color(0xFF94A3B8))),
                const SizedBox(height: 4),
                const Text('Contactez le support pour ajouter un numéro.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(phoneNumbersProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PhoneNumberCard(data: list[i] as Map),
            ),
          );
        },
      ),
    );
  }
}

class _PhoneNumberCard extends StatelessWidget {
  final Map data;
  const _PhoneNumberCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final publicNumber = data['public_number'] as String?
        ?? data['number'] as String?
        ?? data['phone_number'] as String?
        ?? data['e164'] as String?
        ?? '—';

    final technicalNumber = data['technical_number'] as String?
        ?? data['sip_number'] as String?
        ?? data['did'] as String?;

    final providerName = data['provider_name'] as String?
        ?? data['provider'] as String?
        ?? data['carrier'] as String?;

    final label = data['label'] as String?
        ?? data['name'] as String?
        ?? data['description'] as String?;

    // null → true (number exists = active by default)
    final isActive = _safeBoolP(data['is_active'] ?? data['active'])
        ?? (data['status'] != null ? data['status'] == 'active' : true);

    // Linked assistant
    final assistant = data['assistant'] as Map?;
    final assistantName = assistant?['name'] as String?
        ?? (data['assistant_id'] != null ? 'Assistant lié' : null);

    // Call stats if available
    final callsCount = data['calls_count'] as int?
        ?? data['total_calls'] as int?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ───────────────────────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFFEFF6FF)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.phone_rounded,
              size: 20,
              color: isActive
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Expanded(
                  child: Text(
                    publicNumber,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: publicNumber));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Numéro copié'),
                          duration: Duration(seconds: 2)),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.copy_rounded,
                        size: 14, color: Color(0xFF94A3B8)),
                  ),
                ),
              ]),
              if (label != null) ...[
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B))),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          _StatusBadge(active: isActive),
        ]),

        // ── Details ───────────────────────────────────────────
        if (assistantName != null ||
            providerName != null ||
            technicalNumber != null ||
            callsCount != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 8, children: [
            if (assistantName != null)
              _InfoRow(
                icon: Icons.smart_toy_outlined,
                label: 'Assistant',
                value: assistantName,
                color: const Color(0xFF7C3AED),
              ),
            if (providerName != null)
              _InfoRow(
                icon: Icons.business_rounded,
                label: 'Opérateur',
                value: providerName,
                color: const Color(0xFF475569),
              ),
            if (technicalNumber != null)
              _InfoRow(
                icon: Icons.settings_phone_rounded,
                label: 'N° technique',
                value: technicalNumber,
                color: const Color(0xFF475569),
              ),
            if (callsCount != null)
              _InfoRow(
                icon: Icons.phone_in_talk_rounded,
                label: 'Appels',
                value: '$callsCount',
                color: const Color(0xFF2563EB),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFF86EFAC)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF059669)
                  : const Color(0xFFCBD5E1),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Actif' : 'Inactif',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active
                  ? const Color(0xFF059669)
                  : const Color(0xFF94A3B8),
            ),
          ),
        ]),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ]),
      ]);
}

class _ErrorState extends StatelessWidget {
  final Object e;
  final VoidCallback onRetry;
  const _ErrorState({required this.e, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('Impossible de charger les numéros',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            SelectableText(e.toString(),
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ]),
        ),
      );
}
