import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';

final contactsProvider = FutureProvider<List>((ref) async {
  final res = await buildDio().get('/contacts', queryParameters: {'per_page': 200});
  return (res.data['data'] as List?) ?? [];
});

final contactSearchProvider = StateProvider<String>((ref) => '');

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(contactsProvider);
    final search = ref.watch(contactSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher un contact...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(contactSearchProvider.notifier).state = '';
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => ref.read(contactSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 12),
              const Text('Erreur de chargement', style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(contactsProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (list) {
          final filtered = search.isEmpty
              ? list
              : list.where((c) {
                  final name = (c['name'] as String? ?? '').toLowerCase();
                  final phone = (c['phone_number'] as String? ?? '').toLowerCase();
                  final q = search.toLowerCase();
                  return name.contains(q) || phone.contains(q);
                }).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text(
                    search.isNotEmpty ? 'Aucun résultat pour "$search"' : 'Aucun contact',
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(contactsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ContactTile(contact: filtered[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddContactSheet(context),
        backgroundColor: const Color(0xFF2563EB),
        tooltip: 'Ajouter un contact',
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
      ),
    );
  }

  void _showAddContactSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Nouveau contact',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optionnel)',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  try {
                    await buildDio().post('/contacts', data: {
                      'name': nameCtrl.text.trim(),
                      'phone_number': phoneCtrl.text.trim(),
                      if (emailCtrl.text.isNotEmpty) 'email': emailCtrl.text.trim(),
                    });
                    ref.invalidate(contactsProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Erreur lors de l\'ajout')),
                      );
                    }
                  }
                },
                child: const Text('Ajouter le contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Map contact;
  const _ContactTile({required this.contact});

  static const _colors = [
    Color(0xFF7C3AED),
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFF59E0B),
    Color(0xFFDC2626),
    Color(0xFF0891B2),
  ];

  @override
  Widget build(BuildContext context) {
    final name = contact['name'] as String?;
    final phone = contact['phone_number'] as String? ?? '';
    final initials = name != null && name.isNotEmpty ? name[0].toUpperCase() : '?';
    final bgColor = _colors[(initials.codeUnitAt(0)) % _colors.length];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: bgColor.withOpacity(0.15),
          child: Text(
            initials,
            style: TextStyle(color: bgColor, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(
          name ?? phone,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: name != null
            ? Text(phone, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
            : null,
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
        onTap: () => context.go('/contacts/${contact['id']}'),
      ),
    );
  }
}
