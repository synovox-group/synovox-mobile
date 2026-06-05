import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFEFF6FF),
                  radius: 24,
                  child: Text(
                    (user?['name'] as String? ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(user?['email'] ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _Tile(icon: Icons.person_outline, label: 'Mon compte', onTap: () {}),
          _Tile(icon: Icons.notifications_outlined, label: 'Notifications', onTap: () {}),
          _Tile(icon: Icons.language_outlined, label: 'Langue', onTap: () {}),
          _Tile(icon: Icons.info_outline, label: 'À propos', onTap: () {}),
          const SizedBox(height: 16),
          _Tile(
            icon: Icons.logout_rounded,
            label: 'Se déconnecter',
            color: const Color(0xFFDC2626),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF475569)),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 14)),
      trailing: color == null ? const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)) : null,
      onTap: onTap,
    ),
  );
}
