import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_client.dart';
import '../../utils/tz.dart';
import '../appointments/appointments_screen.dart';

final appointmentDetailProvider = FutureProvider.family<Map, int>((ref, id) async {
  final res = await buildDio().get('/appointments/$id');
  return res.data['data'] as Map? ?? res.data as Map? ?? {};
});

// ── Status helpers ─────────────────────────────────────────────────────────────

enum ApptStatus { pending, confirmed, completed, cancelled, unknown }

/// Parse raw API status string to enum (no date inference — use for action buttons)
ApptStatus parseApptStatus(Map data) {
  final raw = (data['status']
          ?? data['state']
          ?? data['appointment_status']
          ?? '') as String;
  return _statusFromRaw(raw, data);
}

String? _extractStartsAt(Map data) =>
    data['starts_at'] as String?
    ?? data['start_at'] as String?
    ?? data['start_time'] as String?
    ?? data['scheduled_at'] as String?;

bool _isApptInPast(Map data) => isApptPast(_extractStartsAt(data));

ApptStatus _statusFromRaw(String raw, Map data) {
  switch (raw.toLowerCase().trim()) {
    case 'cancelled':
    case 'canceled':
    case 'declined':
    case 'rejected':
    case 'no_show':
      return ApptStatus.cancelled;

    case 'completed':
    case 'done':
    case 'finished':
    case 'closed':
      return ApptStatus.completed;

    case 'confirmed':
    case 'approved':
    case 'accepted':
      return ApptStatus.confirmed;

    case 'pending':
    case 'scheduled':
    case 'booked':
    case 'rescheduled':
    case 'active':
    case 'new':
      return ApptStatus.pending;
  }
  // Unknown: infer from date
  final isPast = _isApptInPast(data);
  return isPast ? ApptStatus.completed : ApptStatus.unknown;
}

/// Display status for the LIST — applies date-aware overrides:
/// past + pending/unknown → 'Passé' (completed-style grey)
/// past + confirmed       → 'Terminé' (completed grey)
/// cancelled / completed are always shown as-is
ApptStatus resolveDisplayStatus(Map data) {
  final base = parseApptStatus(data);
  if (base == ApptStatus.cancelled || base == ApptStatus.completed) return base;

  final isPast = _isApptInPast(data);
  if (!isPast) return base; // future: show actual API status

  // Past appointment that the API hasn't yet marked as completed
  return ApptStatus.completed;
}

extension ApptStatusExt on ApptStatus {
  String get label => switch (this) {
        ApptStatus.pending => 'Planifié',
        ApptStatus.confirmed => 'Confirmé',
        ApptStatus.completed => 'Terminé',
        ApptStatus.cancelled => 'Annulé',
        ApptStatus.unknown => 'En attente',
      };

  /// Label used in the list tile when appointment is in the past
  String get pastLabel => switch (this) {
        ApptStatus.cancelled => 'Annulé',
        ApptStatus.completed => 'Terminé',
        _ => 'Passé',
      };
  Color get color => switch (this) {
        ApptStatus.pending => const Color(0xFF2563EB),
        ApptStatus.confirmed => const Color(0xFF059669),
        ApptStatus.completed => const Color(0xFF94A3B8),
        ApptStatus.cancelled => const Color(0xFFDC2626),
        ApptStatus.unknown => const Color(0xFFF59E0B),
      };
  IconData get icon => switch (this) {
        ApptStatus.pending => Icons.schedule_rounded,
        ApptStatus.confirmed => Icons.check_circle_outline_rounded,
        ApptStatus.completed => Icons.task_alt_rounded,
        ApptStatus.cancelled => Icons.cancel_outlined,
        ApptStatus.unknown => Icons.help_outline_rounded,
      };
  bool get canConfirm => this == ApptStatus.pending || this == ApptStatus.unknown;
  bool get canCancel =>
      this == ApptStatus.pending || this == ApptStatus.confirmed || this == ApptStatus.unknown;
  bool get isTerminal =>
      this == ApptStatus.completed || this == ApptStatus.cancelled;
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class AppointmentDetailScreen extends ConsumerWidget {
  final int appointmentId;
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appt = ref.watch(appointmentDetailProvider(appointmentId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        actions: [
          appt.whenOrNull(
            data: (d) {
              final status = parseApptStatus(d);
              if (status.isTerminal) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.edit_calendar_rounded),
                tooltip: 'Reprogrammer',
                onPressed: () => _showRescheduleSheet(context, ref, d),
              );
            },
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: appt.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('Rendez-vous introuvable'),
            TextButton(
              onPressed: () => context.go('/appointments'),
              child: const Text('Retour'),
            ),
          ]),
        ),
        data: (d) =>
            _AppointmentBody(appointmentId: appointmentId, data: d),
      ),
    );
  }

  void _showRescheduleSheet(
      BuildContext context, WidgetRef ref, Map data) {
    DateTime? selected;
    final noteCtrl =
        TextEditingController(text: data['notes'] as String? ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('Reprogrammer',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null || !ctx.mounted) return;
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time == null) return;
                  setModal(() {
                    selected = DateTime(date.year, date.month, date.day,
                        time.hour, time.minute);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: Color(0xFF2563EB)),
                    const SizedBox(width: 12),
                    Text(
                      selected != null
                          ? DateFormat('dd/MM/yyyy HH:mm').format(selected!)
                          : 'Choisir une nouvelle date',
                      style: TextStyle(
                          color: selected != null
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF94A3B8)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optionnel)',
                  prefixIcon: Icon(Icons.notes_rounded),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () async {
                        try {
                          await buildDio().patch(
                              '/appointments/${data['id']}',
                              data: {
                                'starts_at': selected!.toIso8601String(),
                                if (noteCtrl.text.trim().isNotEmpty)
                                  'notes': noteCtrl.text.trim(),
                              });
                          ref.invalidate(appointmentDetailProvider(
                              data['id'] as int));
                          ref.invalidate(appointmentsProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (_) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Erreur lors de la modification')),
                            );
                          }
                        }
                      },
                child: const Text('Confirmer la nouvelle date'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _AppointmentBody extends ConsumerStatefulWidget {
  final int appointmentId;
  final Map data;
  const _AppointmentBody({required this.appointmentId, required this.data});

  @override
  ConsumerState<_AppointmentBody> createState() => _AppointmentBodyState();
}

class _AppointmentBodyState extends ConsumerState<_AppointmentBody> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final status = parseApptStatus(data);
    final title = data['title'] as String?
        ?? data['subject'] as String?
        ?? 'Rendez-vous';
    final notes = data['notes'] as String? ?? data['description'] as String?;

    // Contact — try multiple paths
    final contactMap = data['contact'] as Map?;
    final contactName = contactMap?['name'] as String?
        ?? contactMap?['full_name'] as String?
        ?? data['contact_name'] as String?
        ?? data['client_name'] as String?;
    final contactPhone = contactMap?['phone_number'] as String?
        ?? contactMap?['phone'] as String?
        ?? data['contact_phone'] as String?;

    // Date — parsed in Europe/Zurich timezone
    final startsAtRaw = _extractStartsAt(data);
    final DateTime? startsAt = parseZurich(startsAtRaw);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Status banner ─────────────────────────────────────
        _StatusBanner(status: status),
        const SizedBox(height: 12),

        // ── Header card ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(status.icon, color: status.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      decoration: status == ApptStatus.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                      color: status == ApptStatus.cancelled
                          ? const Color(0xFF94A3B8)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StatusBadge(status: status),
                ]),
              ),
            ]),
            if (startsAt != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.calendar_month_rounded,
                text: _fmtDate(startsAt),
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.access_time_rounded,
                text: DateFormat('HH:mm').format(startsAt) +
                    (data['duration_minutes'] != null
                        ? '  ·  ${data['duration_minutes']} min'
                        : ''),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // ── Contact ───────────────────────────────────────────
        if (contactName != null || contactPhone != null) ...[
          const _SectionHeader(
              title: 'Contact', icon: Icons.person_outline_rounded),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFF5F3FF),
                child: Text(
                  (contactName ?? contactPhone ?? '?')[0].toUpperCase(),
                  style: const TextStyle(
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(contactName ?? contactPhone ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: contactName != null && contactPhone != null
                  ? Text(contactPhone,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF94A3B8)))
                  : null,
              trailing: contactPhone != null
                  ? IconButton(
                      icon: const Icon(Icons.phone_rounded,
                          color: Color(0xFF2563EB)),
                      onPressed: () async {
                        final uri = Uri(scheme: 'tel', path: contactPhone);
                        if (await canLaunchUrl(uri)) launchUrl(uri);
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Notes ─────────────────────────────────────────────
        if (notes != null && notes.isNotEmpty) ...[
          const _SectionHeader(
              title: 'Notes', icon: Icons.notes_rounded),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Text(notes,
                style: const TextStyle(
                    fontSize: 14, height: 1.6, color: Color(0xFF0F172A))),
          ),
          const SizedBox(height: 16),
        ],

        // ── Action buttons ────────────────────────────────────
        if (!status.isTerminal) ...[
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 16),
          _ActionButtons(
            status: status,
            loading: _loading,
            onConfirm: status.canConfirm ? () => _doAction('confirmed') : null,
            onCancel: status.canCancel ? () => _confirmCancel() : null,
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  String _fmtDate(DateTime dt) {
    try {
      return DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(dt);
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(dt);
    }
  }
  // dt is already in Zurich time — format directly

  Future<void> _doAction(String newStatus) async {
    setState(() => _loading = true);
    try {
      await buildDio().patch('/appointments/${widget.appointmentId}',
          data: {'status': newStatus});
      ref.invalidate(appointmentDetailProvider(widget.appointmentId));
      ref.invalidate(appointmentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus == 'confirmed'
                ? 'Rendez-vous confirmé ✓'
                : 'Rendez-vous annulé'),
            backgroundColor: newStatus == 'confirmed'
                ? const Color(0xFF059669)
                : const Color(0xFF64748B),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise à jour')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler le rendez-vous ?'),
        content:
            const Text('Cette action est définitive. Le contact sera notifié.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Retour')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            onPressed: () {
              Navigator.pop(ctx);
              _doAction('cancelled');
            },
            child: const Text('Confirmer l\'annulation',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final ApptStatus status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status.color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(status.icon, size: 16, color: status.color),
        const SizedBox(width: 8),
        Text(status.label,
            style: TextStyle(
                color: status.color,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
        const Spacer(),
        if (status == ApptStatus.pending || status == ApptStatus.unknown)
          Text('Action requise',
              style: TextStyle(
                  fontSize: 11,
                  color: status.color.withValues(alpha: 0.7))),
        if (status == ApptStatus.confirmed)
          Text('Rendez-vous confirmé',
              style: TextStyle(
                  fontSize: 11,
                  color: status.color.withValues(alpha: 0.7))),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ApptStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(status.label,
            style: TextStyle(
                fontSize: 12,
                color: status.color,
                fontWeight: FontWeight.w500)),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ]);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600)),
      ]);
}

class _ActionButtons extends StatelessWidget {
  final ApptStatus status;
  final bool loading;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  const _ActionButtons({
    required this.status,
    required this.loading,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (onConfirm != null)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('Confirmer le rendez-vous'),
            onPressed: loading ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      if (onCancel != null) ...[
        if (onConfirm != null) const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.cancel_outlined, size: 18,
                color: Color(0xFFDC2626)),
            label: const Text('Annuler le rendez-vous',
                style: TextStyle(color: Color(0xFFDC2626))),
            onPressed: loading ? null : onCancel,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFDC2626)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ],
    ]);
  }
}
