import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../utils/tz.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_client.dart';

final contactDetailProvider = FutureProvider.family<Map, int>((ref, id) async {
  final res = await buildDio().get('/contacts/$id');
  return res.data['data'] as Map? ?? {};
});

final contactCallsProvider = FutureProvider.family<List, int>((ref, contactId) async {
  final res = await buildDio().get('/calls', queryParameters: {
    'contact_id': contactId,
    'per_page': 20,
  });
  return (res.data['data'] as List?) ?? [];
});

class ContactDetailScreen extends ConsumerWidget {
  final int contactId;
  const ContactDetailScreen({super.key, required this.contactId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactDetailProvider(contactId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact'),
        actions: [
          contact.whenOrNull(
            data: (data) => IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showEditSheet(context, ref, data),
            ),
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: contact.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 12),
              const Text('Contact introuvable'),
              TextButton(
                onPressed: () => context.go('/contacts'),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
        data: (data) => _ContactBody(contactId: contactId, data: data),
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, Map data) {
    final nameCtrl = TextEditingController(text: data['name'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: data['phone_number'] as String? ?? '');
    final emailCtrl = TextEditingController(text: data['email'] as String? ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Modifier le contact',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  await buildDio().put('/contacts/${data['id']}', data: {
                    'name': nameCtrl.text.trim(),
                    'phone_number': phoneCtrl.text.trim(),
                    if (emailCtrl.text.isNotEmpty) 'email': emailCtrl.text.trim(),
                  });
                  ref.invalidate(contactDetailProvider(contactId));
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Erreur lors de la modification')),
                    );
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactBody extends ConsumerWidget {
  final int contactId;
  final Map data;
  const _ContactBody({required this.contactId, required this.data});

  static const _colors = [
    Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF059669),
    Color(0xFFF59E0B), Color(0xFFDC2626), Color(0xFF0891B2),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(contactCallsProvider(contactId));
    final name = data['name'] as String? ?? '';
    final phone = data['phone_number'] as String? ?? '—';
    final email = data['email'] as String?;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = _colors[(initials.codeUnitAt(0)) % _colors.length];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: color.withOpacity(0.15),
                child: Text(
                  initials,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(height: 12),
              if (name.isNotEmpty)
                Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(phone, style: const TextStyle(fontSize: 15, color: Color(0xFF64748B))),
              if (email != null) ...[
                const SizedBox(height: 2),
                Text(email, style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: const Text('Appeler'),
                    onPressed: () async {
                      final uri = Uri(scheme: 'tel', path: phone);
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF2563EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (email != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: const Text('Email'),
                      onPressed: () async {
                        final uri = Uri(scheme: 'mailto', path: email);
                        if (await canLaunchUrl(uri)) launchUrl(uri);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7C3AED),
                        side: const BorderSide(color: Color(0xFF7C3AED)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Call history
        const Row(children: [
          Icon(Icons.history_rounded, size: 16, color: Color(0xFF2563EB)),
          SizedBox(width: 6),
          Text('Historique des appels',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        calls.when(
          loading: () => const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )),
          error: (_, __) => const Text('Impossible de charger les appels',
              style: TextStyle(color: Color(0xFF94A3B8))),
          data: (list) {
            if (list.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Center(
                  child: Text('Aucun appel pour ce contact',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                ),
              );
            }
            return Column(
              children: list.map<Widget>((c) {
                final status = c['status'] as String? ?? '';
                final clr = status == 'completed'
                    ? const Color(0xFF059669)
                    : status == 'missed'
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF94A3B8);
                final dateStr = fmtDateTime(c['started_at'] as String?, fallback: '');
                final seconds = c['duration_seconds'] as int? ?? 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: clr.withOpacity(0.1),
                      child: Icon(
                        status == 'missed' ? Icons.phone_missed_rounded : Icons.phone_rounded,
                        color: clr,
                        size: 18,
                      ),
                    ),
                    title: Text(dateStr,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      _formatDuration(seconds),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
                    onTap: () => context.go('/calls/${c['id']}'),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '—';
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m${(seconds % 60).toString().padLeft(2, '0')}s';
  }
}
