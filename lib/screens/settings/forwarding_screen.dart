import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../services/app_cache.dart';

bool _parseBool(dynamic v) {
  if (v == null) return false; // forwarding inactive by default if not set
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == '1' || s == 'true' || s == 'active' || s == 'on' || s == 'enabled';
  }
  return false;
}

class _ForwardingNotifier extends AsyncNotifier<List> {
  static const _key = 'forwarding_configs';

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
    final res = await buildDio().get('/forwarding-configs');
    final raw = res.data;
    List data;
    if (raw is Map) {
      final d = raw['data'];
      data = d is List ? d : [];
    } else if (raw is List) {
      data = raw;
    } else {
      data = [];
    }
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

final forwardingProvider =
    AsyncNotifierProvider<_ForwardingNotifier, List>(_ForwardingNotifier.new);

class ForwardingScreen extends ConsumerWidget {
  const ForwardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(forwardingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Renvoi d\'appels')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context, ref, null),
        backgroundColor: const Color(0xFF2563EB),
        tooltip: 'Ajouter',
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 12),
              const Text('Impossible de charger les renvois'),
              const SizedBox(height: 8),
              SelectableText(
                e.toString(),
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(forwardingProvider),
                child: const Text('Réessayer'),
              ),
            ]),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.call_missed_outgoing_rounded,
                    size: 52, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text('Aucun renvoi configuré',
                    style: TextStyle(color: Color(0xFF94A3B8))),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(forwardingProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ForwardingTile(
                config: list[i] as Map,
                onToggle: (active) => _toggle(context, ref, list[i]['id'], active),
                onEdit: () => _showAddSheet(context, ref, list[i] as Map),
                onDelete: () => _delete(context, ref, list[i]['id']),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, dynamic id, bool activate) async {
    try {
      final endpoint = activate
          ? '/forwarding-configs/$id/activate'
          : '/forwarding-configs/$id/deactivate';
      await buildDio().post(endpoint);
      ref.read(forwardingProvider.notifier).refresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise à jour')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce renvoi ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await buildDio().delete('/forwarding-configs/$id');
      ref.read(forwardingProvider.notifier).refresh();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
      }
    }
  }

  void _showAddSheet(BuildContext context, WidgetRef ref, Map? existing) {
    final nameCtrl = TextEditingController(
        text: _extractStr(existing?['name'], ''));
    final phoneCtrl = TextEditingController(
        text: _extractPhone(existing?['phone_number']
            ?? existing?['forward_to']
            ?? existing?['destination']));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(existing == null ? 'Nouveau renvoi' : 'Modifier le renvoi',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nom du renvoi',
                  prefixIcon: Icon(Icons.label_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Numéro de renvoi',
                  hintText: '+41791234567',
                  prefixIcon: Icon(Icons.call_missed_outgoing_rounded)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Remplissez tous les champs')),
                  );
                  return;
                }
                try {
                  final payload = {
                    'name': nameCtrl.text.trim(),
                    'phone_number': phoneCtrl.text.trim(),
                  };
                  if (existing == null) {
                    await buildDio().post('/forwarding-configs', data: payload);
                  } else {
                    await buildDio()
                        .patch('/forwarding-configs/${existing['id']}', data: payload);
                  }
                  ref.read(forwardingProvider.notifier).refresh();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Erreur lors de la sauvegarde')),
                    );
                  }
                }
              },
              child: Text(existing == null ? 'Créer' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

// phone_number can be a String or a nested Map (Laravel relationship)
String _extractPhone(dynamic v) {
  if (v == null) return '—';
  if (v is String) return v;
  if (v is Map) {
    return v['number'] as String?
        ?? v['phone_number'] as String?
        ?? v['e164'] as String?
        ?? v['formatted'] as String?
        ?? v['value'] as String?
        ?? v.values.whereType<String>().firstOrNull
        ?? '—';
  }
  return '$v';
}

String _extractStr(dynamic v, String fallback) {
  if (v == null) return fallback;
  if (v is String) return v;
  if (v is Map) return v['name'] as String? ?? v.values.whereType<String>().firstOrNull ?? fallback;
  return '$v';
}

class _ForwardingTile extends StatelessWidget {
  final Map config;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ForwardingTile({
    required this.config,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = _extractStr(config['name'], 'Renvoi');
    final phone = _extractPhone(
        config['phone_number'] ?? config['forward_to'] ?? config['destination']);
    final isActive = _parseBool(config['is_active'] ?? config['active'] ?? config['status']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFF0FDF4)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.call_missed_outgoing_rounded,
                size: 18,
                color: isActive
                    ? const Color(0xFF059669)
                    : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(phone,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B))),
              ]),
            ),
            Switch(
              value: isActive,
              onChanged: onToggle,
              activeColor: const Color(0xFF059669),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _chip(
              isActive ? 'Actif' : 'Inactif',
              isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
              color: const Color(0xFF64748B),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: onDelete,
              color: const Color(0xFFDC2626),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );
}
