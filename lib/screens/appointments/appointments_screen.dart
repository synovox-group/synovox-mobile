import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../utils/tz.dart';
import '../appointments/appointment_detail_screen.dart'
    show parseApptStatus, resolveDisplayStatus, ApptStatusExt, ApptStatus;

final appointmentsProvider = FutureProvider<List>((ref) async {
  final res = await buildDio().get('/appointments', queryParameters: {'per_page': 100});
  return (res.data['data'] as List?) ?? [];
});

enum ApptFilter { all, upcoming, past, cancelled }

final apptFilterProvider = StateProvider<ApptFilter>((ref) => ApptFilter.all);

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appointmentsProvider);
    final filter = ref.watch(apptFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rendez-vous')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _FilterChip(label: 'Tous', filter: ApptFilter.all, current: filter),
                const SizedBox(width: 8),
                _FilterChip(label: 'À venir', filter: ApptFilter.upcoming, current: filter),
                const SizedBox(width: 8),
                _FilterChip(label: 'Passés', filter: ApptFilter.past, current: filter),
                const SizedBox(width: 8),
                _FilterChip(label: 'Annulés', filter: ApptFilter.cancelled, current: filter),
              ],
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
                    const SizedBox(height: 12),
                    const Text('Erreur de chargement',
                        style: TextStyle(color: Color(0xFF64748B))),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(appointmentsProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (list) {
                final filtered = _filterAppts(list, filter);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        const Text('Aucun rendez-vous',
                            style: TextStyle(color: Color(0xFF94A3B8))),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(appointmentsProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _ApptTile(appt: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddApptSheet(context, ref),
        backgroundColor: const Color(0xFF059669),
        tooltip: 'Nouveau rendez-vous',
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  List _filterAppts(List list, ApptFilter filter) {
    return list.where((a) {
      final raw = a['status'] as String? ?? '';
      final cancelled = raw == 'cancelled' || raw == 'canceled';
      final startsAt = a['starts_at'] as String? ?? a['start_at'] as String?
          ?? a['start_time'] as String? ?? a['scheduled_at'] as String?;
      final past = isApptPast(startsAt);

      if (filter == ApptFilter.cancelled) return cancelled;
      if (filter == ApptFilter.upcoming) return !cancelled && !past;
      if (filter == ApptFilter.past) return !cancelled && past;
      return true;
    }).toList();
  }

  void _showAddApptSheet(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    DateTime? selectedDate;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding:
              EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Nouveau rendez-vous',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Titre',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;
                    setModalState(() {
                      selectedDate = DateTime(
                          date.year, date.month, date.day, time.hour, time.minute);
                    });
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
                            ? '${selectedDate!.day.toString().padLeft(2,'0')}/${selectedDate!.month.toString().padLeft(2,'0')}/${selectedDate!.year} ${selectedDate!.hour.toString().padLeft(2,'0')}:${selectedDate!.minute.toString().padLeft(2,'0')}'
                            : 'Choisir une date et heure',
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
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Veuillez choisir une date')),
                      );
                      return;
                    }
                    final date = selectedDate!;
                    try {
                      await buildDio().post('/appointments', data: {
                        'title': titleCtrl.text.trim(),
                        'starts_at': date.toIso8601String(),
                      });
                      ref.invalidate(appointmentsProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (_) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Erreur lors de la création')),
                        );
                      }
                    }
                  },
                  child: const Text('Créer le rendez-vous'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends ConsumerWidget {
  final String label;
  final ApptFilter filter;
  final ApptFilter current;
  const _FilterChip({required this.label, required this.filter, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = filter == current;
    return GestureDetector(
      onTap: () => ref.read(apptFilterProvider.notifier).state = filter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF059669) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

class _ApptTile extends StatelessWidget {
  final Map appt;
  const _ApptTile({required this.appt});

  @override
  Widget build(BuildContext context) {
    // resolveDisplayStatus applies date-aware logic for the list view
    final rawStatus = parseApptStatus(appt);
    final displayStatus = resolveDisplayStatus(appt);
    final color = displayStatus.color;
    final isCancelled = displayStatus == ApptStatus.cancelled;

    // Determine if appointment is in the past for label selection
    bool isPast = false;
    final startsAtRaw = appt['starts_at'] as String?
        ?? appt['start_at'] as String?
        ?? appt['start_time'] as String?
        ?? appt['scheduled_at'] as String?;

    String dateDay = '';
    String dateMonth = '';
    String timeStr = '';
    final DateTime? dt = parseZurich(startsAtRaw);
    if (dt != null) {
      isPast = isApptPast(startsAtRaw);
      dateDay = fmtDate(startsAtRaw, fallback: '').split(' ').first;
      dateMonth = fmtDate(startsAtRaw, fallback: '').split(' ').elementAtOrNull(1) ?? '';
      timeStr = fmtTime(startsAtRaw, fallback: '');
    }

    // Badge label: past appointments without explicit terminal status → "Passé"
    final badgeLabel = isPast && rawStatus != ApptStatus.cancelled && rawStatus != ApptStatus.completed
        ? 'Passé'
        : displayStatus.label;

    final contactName = (appt['contact'] as Map?)?['name'] as String?
        ?? (appt['contact'] as Map?)?['full_name'] as String?
        ?? appt['contact_name'] as String?
        ?? appt['client_name'] as String?;
    final contactPhone = (appt['contact'] as Map?)?['phone_number'] as String?
        ?? (appt['contact'] as Map?)?['phone'] as String?;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(dateDay,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: color)),
              Text(dateMonth,
                  style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
        title: Text(
          appt['title'] as String? ?? appt['subject'] as String? ?? 'Rendez-vous',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            decoration: isCancelled ? TextDecoration.lineThrough : null,
            color: isCancelled ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.access_time_rounded, size: 12, color: color),
              const SizedBox(width: 4),
              Text(timeStr,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            if (contactName != null || contactPhone != null) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.person_outline_rounded,
                    size: 11, color: Color(0xFF94A3B8)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    contactName ?? contactPhone!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ],
          ],
        ),
        isThreeLine: contactName != null || contactPhone != null,
        trailing: const Icon(Icons.chevron_right_rounded,
            color: Color(0xFFCBD5E1)),
        onTap: () => context.go('/appointments/${appt['id']}'),
      ),
    );
  }
}
