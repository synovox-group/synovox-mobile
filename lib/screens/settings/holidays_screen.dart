import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../utils/tz.dart';

final holidaysProvider = FutureProvider<List>((ref) async {
  final res = await buildDio().get('/holidays');
  return (res.data['data'] as List?) ?? (res.data as List?) ?? [];
});

class HolidaysScreen extends ConsumerWidget {
  const HolidaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(holidaysProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Jours fériés / Fermetures')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context, ref),
        backgroundColor: const Color(0xFF2563EB),
        tooltip: 'Ajouter',
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('Impossible de charger les fermetures'),
            TextButton(
              onPressed: () => ref.invalidate(holidaysProvider),
              child: const Text('Réessayer'),
            ),
          ]),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.event_busy_rounded, size: 52, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text('Aucune fermeture définie',
                    style: TextStyle(color: Color(0xFF94A3B8))),
                const SizedBox(height: 4),
                const Text('L\'assistant répondra tous les jours.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(holidaysProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _HolidayTile(
                holiday: list[i] as Map,
                onDelete: () => _delete(context, ref, list[i]['id']),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette fermeture ?'),
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
      await buildDio().delete('/holidays/$id');
      ref.invalidate(holidaysProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
      }
    }
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    DateTime? selectedDate;
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Text('Ajouter une fermeture',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Libellé (ex: Noël)',
                      prefixIcon: Icon(Icons.label_outline)),
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (date != null) setModal(() => selectedDate = date);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 12),
                      Text(
                        selectedDate != null
                            ? fmtDate(selectedDate!.toIso8601String())
                            : 'Choisir une date',
                        style: TextStyle(
                          color: selectedDate != null
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedDate == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Choisissez une date')),
                      );
                      return;
                    }
                    try {
                      await buildDio().post('/holidays', data: {
                        'date': '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}',
                        'name': nameCtrl.text.trim(),
                      });
                      ref.invalidate(holidaysProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (_) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Erreur lors de la création')),
                        );
                      }
                    }
                  },
                  child: const Text('Ajouter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HolidayTile extends StatelessWidget {
  final Map holiday;
  final VoidCallback onDelete;
  const _HolidayTile({required this.holiday, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = holiday['name'] as String? ?? '—';
    final dateStr = fmtDate(holiday['date'] as String?);
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.event_busy_rounded,
              size: 20, color: Color(0xFFF59E0B)),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(dateStr,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: Color(0xFFDC2626), size: 20),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
