import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../services/api_client.dart';

final appointmentsProvider = FutureProvider<List>((ref) async {
  final res = await buildDio().get('/appointments', queryParameters: {'per_page': 50});
  return (res.data['data'] as List?) ?? [];
});

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appointmentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rendez-vous')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Aucun rendez-vous', style: TextStyle(color: Color(0xFF94A3B8))))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final a = list[i];
                  String dateStr = '';
                  try { dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(a['starts_at'])); } catch (_) {}
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFECFDF5),
                        child: Icon(Icons.calendar_today_rounded, color: Color(0xFF059669), size: 18),
                      ),
                      title: Text(a['title'] ?? 'Rendez-vous', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(dateStr, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
