import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/tz.dart';
import '../../widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final stats = ref.watch(dashboardProvider);
    final greeting = _greeting();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(greeting, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            Text(
              user?['name'] ?? 'Synovox',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(dashboardProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: stats.when(
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
                  onPressed: () => ref.invalidate(dashboardProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
          data: (data) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Stats grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  StatCard(
                    label: 'Appels aujourd\'hui',
                    value: '${data['calls_today'] ?? 0}',
                    icon: Icons.phone_in_talk_rounded,
                    color: const Color(0xFF2563EB),
                    onTap: () => context.go('/calls'),
                  ),
                  StatCard(
                    label: 'RDV cette semaine',
                    value: '${data['appointments_week'] ?? 0}',
                    icon: Icons.calendar_today_rounded,
                    color: const Color(0xFF059669),
                    onTap: () => context.go('/appointments'),
                  ),
                  StatCard(
                    label: 'Contacts',
                    value: '${data['total_contacts'] ?? 0}',
                    icon: Icons.people_outline_rounded,
                    color: const Color(0xFF7C3AED),
                    onTap: () => context.go('/contacts'),
                  ),
                  StatCard(
                    label: (data['assistant_name'] as String?)?.isNotEmpty == true
                        ? data['assistant_name'] as String
                        : 'Assistant',
                    value: (data['assistant_active'] == true) ? 'Actif' : 'Inactif',
                    icon: Icons.smart_toy_outlined,
                    color: (data['assistant_active'] == true)
                        ? const Color(0xFF059669)
                        : const Color(0xFF94A3B8),
                    onTap: () => context.go('/assistants'),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Recent calls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Derniers appels',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  TextButton(
                    onPressed: () => context.go('/calls'),
                    child: const Text('Voir tout',
                        style: TextStyle(fontSize: 13, color: Color(0xFF2563EB))),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if ((data['recent_calls'] as List?)?.isEmpty ?? true)
                _emptyState('Aucun appel récent')
              else
                ...(data['recent_calls'] as List)
                    .take(5)
                    .map((c) => _callTile(context, c)),

              // Upcoming appointments
              if ((data['upcoming_appointments'] as List?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Prochains rendez-vous',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    TextButton(
                      onPressed: () => context.go('/appointments'),
                      child: const Text('Voir tout',
                          style: TextStyle(fontSize: 13, color: Color(0xFF2563EB))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...(data['upcoming_appointments'] as List)
                    .take(3)
                    .map((a) => _apptTile(context, a)),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bonne après-midi';
    return 'Bonsoir';
  }

  Widget _callTile(BuildContext context, dynamic raw) {
    final c = raw as Map;
    final status = c['status'] as String? ?? 'completed';
    final isMissed = status == 'missed' || status == 'no_answer';
    final color = isMissed ? const Color(0xFFDC2626) : const Color(0xFF059669);
    final icon = isMissed ? Icons.phone_missed_rounded : Icons.phone_rounded;
    final dateStr = fmtCompact(c['started_at'] as String? ?? c['created_at'] as String?);

    // Contact name from nested contact object or direct field
    final contact = c['contact'] as Map?;
    final contactName = contact?['name'] as String?
        ?? contact?['full_name'] as String?
        ?? c['contact_name'] as String?;
    final number = c['caller_number'] as String?
        ?? c['from_number'] as String?
        ?? '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: contactName != null
              ? Text(contactName[0].toUpperCase(),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 14))
              : Icon(icon, color: color, size: 18),
        ),
        title: Text(
          contactName ?? number,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          contactName != null ? '$number · $dateStr' : dateStr,
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: Color(0xFFCBD5E1)),
        onTap: () => context.go('/calls/${c['id']}'),
      ),
    );
  }

  Widget _apptTile(BuildContext context, Map a) {
    final dateStr = fmtCompact(
      a['starts_at'] as String? ?? a['start_at'] as String?
          ?? a['start_time'] as String?,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFECFDF5),
          child: Icon(Icons.calendar_today_rounded, color: Color(0xFF059669), size: 18),
        ),
        title: Text(
          a['title'] ?? 'Rendez-vous',
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(dateStr,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
        onTap: () => context.go('/appointments/${a['id']}'),
      ),
    );
  }

  Widget _emptyState(String msg) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Text(msg,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
        ),
      );
}
