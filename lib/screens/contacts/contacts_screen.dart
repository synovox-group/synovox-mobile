import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';

final contactsProvider = FutureProvider<List>((ref) async {
  final res = await buildDio().get('/contacts', queryParameters: {'per_page': 100});
  return (res.data['data'] as List?) ?? [];
});

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Aucun contact', style: TextStyle(color: Color(0xFF94A3B8))))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = list[i];
                  final name = c['name'] as String?;
                  final initials = name != null && name.isNotEmpty ? name[0].toUpperCase() : '?';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF5F3FF),
                        child: Text(initials, style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w700)),
                      ),
                      title: Text(name ?? c['phone_number'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                      subtitle: Text(c['phone_number'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
