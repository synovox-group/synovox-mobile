import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../services/app_cache.dart';

class _AssistantsNotifier extends AsyncNotifier<List> {
  static const _key = 'assistants';

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
    final res = await buildDio().get('/assistants');
    final data = _safeList(res.data);
    // Apply cached active state only when API returns no explicit value
    for (final item in data) {
      if (item is Map) {
        final apiVal = item['is_active'] ?? item['active'];
        if (apiVal == null) {
          final id = item['id'];
          if (id != null) {
            final cached = await AppCache.loadBool('assistant_active_$id');
            if (cached != null) (item as dynamic)['is_active'] = cached;
          }
        }
      }
    }
    await AppCache.saveJson(_key, data);
    return data;
  }

  Future<void> _backgroundRefresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (_) {}
  }
}

final assistantsProvider =
    AsyncNotifierProvider<_AssistantsNotifier, List>(_AssistantsNotifier.new);

/// null / missing field → true (configured assistant = active by default, matches web)
bool _parseBool(dynamic v) {
  if (v == null) return true;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'active' || s == 'on';
  }
  return true;
}

List _safeList(dynamic raw) {
  if (raw is List) return raw;
  if (raw is Map) {
    for (final key in ['data', 'assistants', 'items', 'results']) {
      final v = raw[key];
      if (v is List) return v;
      if (v is Map) return [v];
    }
    if ((raw as Map).isNotEmpty) return [raw];
  }
  return [];
}

class AssistantsScreen extends ConsumerWidget {
  const AssistantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(assistantsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Assistants IA')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 12),
              const Text('Erreur de chargement', style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(assistantsProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Aucun assistant configuré',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  const SizedBox(height: 8),
                  const Text(
                    'Configurez votre premier assistant\ndepuis le tableau de bord web.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(assistantsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _AssistantCard(assistant: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _AssistantCard extends StatelessWidget {
  final Map assistant;
  const _AssistantCard({required this.assistant});

  @override
  Widget build(BuildContext context) {
    final name = assistant['name'] as String? ?? 'Assistant';
    final language = (assistant['language'] as String? ?? 'fr').toUpperCase();
    final sector = assistant['sector'] as String? ?? 'Général';
    final isActive = _parseBool(
        assistant['is_active'] ?? assistant['active'] ?? assistant['status']);
    final callsHandled = assistant['calls_handled'] as int? ?? 0;
    final phoneNumber = assistant['phone_number'] as String?;

    return GestureDetector(
      onTap: () => context.go('/assistants/${assistant['id']}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? const Color(0xFF2563EB).withOpacity(0.3) : const Color(0xFFE2E8F0),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF2563EB).withOpacity(0.1)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.smart_toy_rounded,
                    color: isActive ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '$language · $sector',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ]),
                ),
                _ActiveBadge(isActive: isActive),
              ]),
              if (phoneNumber != null || callsHandled > 0) ...[
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
                Row(children: [
                  if (phoneNumber != null) ...[
                    const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      phoneNumber,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const Spacer(),
                  ],
                  if (callsHandled > 0) ...[
                    const Icon(Icons.call_received_rounded, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      '$callsHandled appel${callsHandled > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ],
                ]),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Voir la configuration',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF2563EB)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  const _ActiveBadge({required this.isActive});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF059669).withOpacity(0.1)
              : const Color(0xFF94A3B8).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isActive ? 'Actif' : 'Inactif',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8),
            ),
          ),
        ]),
      );
}
