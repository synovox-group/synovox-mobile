import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';

final assistantsProvider = FutureProvider<List>((ref) async {
  final res = await buildDio().get('/assistants');
  return (res.data['data'] as List?) ?? [];
});

class AssistantsScreen extends ConsumerWidget {
  const AssistantsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(assistantsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Assistants')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Aucun assistant', style: TextStyle(color: Color(0xFF94A3B8))))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final a = list[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFEFF6FF),
                        child: const Icon(Icons.smart_toy_outlined, color: Color(0xFF2563EB), size: 20),
                      ),
                      title: Text(a['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${a['language']?.toUpperCase() ?? ''} · ${a['sector'] ?? 'Général'}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
