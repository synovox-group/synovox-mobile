import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';

final callDetailProvider = FutureProvider.family<Map, int>((ref, id) async {
  final res = await buildDio().get('/calls/$id');
  return res.data['data'] as Map? ?? {};
});

class CallDetailScreen extends ConsumerWidget {
  final int callId;
  const CallDetailScreen({super.key, required this.callId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callDetailProvider(callId));
    return Scaffold(
      appBar: AppBar(title: const Text('Détail appel')),
      body: call.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoCard(label: 'Numéro', value: data['caller_number'] ?? '—'),
            _InfoCard(label: 'Statut', value: data['status'] ?? '—'),
            _InfoCard(label: 'Durée', value: '${data['duration_seconds'] ?? 0}s'),
            if (data['summary_text'] != null) ...[
              const SizedBox(height: 16),
              Text('Résumé', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Text(data['summary_text'], style: const TextStyle(fontSize: 14, height: 1.6)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label, value;
  const _InfoCard({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
    ),
  );
}
