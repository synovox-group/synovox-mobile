import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/api_client.dart';

final callsProvider = FutureProvider<List>((ref) async {
  final res = await buildDio().get('/calls', queryParameters: {'per_page': 50});
  return (res.data['data'] as List?) ?? [];
});

class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(callsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Appels')),
      body: calls.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Aucun appel', style: TextStyle(color: Color(0xFF94A3B8))))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CallTile(call: list[i]),
              ),
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  final Map call;
  const _CallTile({required this.call});

  @override
  Widget build(BuildContext context) {
    final status = call['status'] as String? ?? '';
    final color = status == 'completed' ? const Color(0xFF059669) : const Color(0xFF94A3B8);
    String dateStr = '';
    try {
      dateStr = DateFormat('dd/MM HH:mm').format(DateTime.parse(call['started_at']));
    } catch (_) {}

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(Icons.phone_rounded, color: color, size: 18),
        ),
        title: Text(call['caller_number'] ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text('$dateStr · ${call['duration_seconds'] ?? 0}s',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
        onTap: () => context.go('/calls/${call['id']}'),
      ),
    );
  }
}
