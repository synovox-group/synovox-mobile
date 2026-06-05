import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user  = ref.watch(authProvider).user;
    final stats = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bonjour 👋', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            Text(user?['name'] ?? 'Synovox',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
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
                    label: 'Assistant actif',
                    value: (data['assistant_active'] == true) ? 'Actif' : 'Inactif',
                    icon: Icons.smart_toy_outlined,
                    color: const Color(0xFFF59E0B),
                    onTap: () => context.go('/assistants'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent calls
              const Text('Derniers appels',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if ((data['recent_calls'] as List?)?.isEmpty ?? true)
                _emptyState('Aucun appel récent')
              else
                ...(data['recent_calls'] as List).take(5).map((c) => _callTile(context, c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _callTile(BuildContext context, Map c) {
    final status = c['status'] as String? ?? 'completed';
    final color  = status == 'completed' ? const Color(0xFF059669) : const Color(0xFF64748B);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(Icons.phone_rounded, color: color, size: 18),
        ),
        title: Text(c['caller_number'] ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(c['started_at'] ?? '',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
        onTap: () => context.go('/calls/${c['id']}'),
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
