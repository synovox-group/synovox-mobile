import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/api_client.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name = user?['name'] as String? ?? 'Utilisateur';
    final email = user?['email'] as String? ?? '';
    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 60),
        children: [
          // ── Profile card ──────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFEFF6FF),
                  child: Text(initials,
                      style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700,
                          fontSize: 20)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(email,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF64748B))),
                  ]),
                ),
                TextButton(
                  onPressed: () => _showEditProfile(context, ref, user),
                  child: const Text('Modifier'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Compte ────────────────────────────────────────
          const _SectionLabel(label: 'Compte'),
          _Tile(
            icon: Icons.person_outline,
            label: 'Mon profil',
            onTap: () => _showEditProfile(context, ref, user),
          ),
          _Tile(
            icon: Icons.lock_outline,
            label: 'Changer le mot de passe',
            onTap: () => _showChangePassword(context),
          ),
          const SizedBox(height: 16),

          // ── Configuration assistant ───────────────────────
          const _SectionLabel(label: 'Assistant & Téléphonie'),
          _Tile(
            icon: Icons.phone_rounded,
            label: 'Numéros de téléphone',
            onTap: () => context.go('/settings/phone-numbers'),
          ),
          _Tile(
            icon: Icons.schedule_rounded,
            label: 'Horaires d\'ouverture',
            onTap: () => context.go('/settings/business-hours'),
          ),
          _Tile(
            icon: Icons.event_busy_rounded,
            label: 'Jours fériés / Fermetures',
            onTap: () => context.go('/settings/holidays'),
          ),
          _Tile(
            icon: Icons.call_missed_outgoing_rounded,
            label: 'Renvoi d\'appels',
            onTap: () => context.go('/settings/forwarding'),
          ),
          _Tile(
            icon: Icons.bar_chart_rounded,
            label: 'Analytiques',
            onTap: () => context.go('/analytics'),
          ),
          const SizedBox(height: 16),

          // ── Notifications dynamiques ──────────────────────
          const _SectionLabel(label: 'Notifications'),
          const _NotificationsSection(),
          const SizedBox(height: 16),

          // ── App ───────────────────────────────────────────
          const _SectionLabel(label: 'Application'),
          _Tile(
            icon: Icons.language_outlined,
            label: 'Langue',
            trailing: const Text('Français',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            onTap: () => _showLanguagePicker(context),
          ),
          _Tile(
            icon: Icons.info_outline,
            label: 'À propos',
            onTap: () => _showAbout(context),
          ),
          const SizedBox(height: 16),

          // ── Danger ────────────────────────────────────────
          _Tile(
            icon: Icons.logout_rounded,
            label: 'Se déconnecter',
            color: const Color(0xFFDC2626),
            onTap: () => _confirmLogout(context, ref),
          ),
          const SizedBox(height: 32),
          const Center(
            child: Text('Synovox v1.0.0',
                style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
          ),
        ],
      ),
    );
  }

  void _showEditProfile(BuildContext context, WidgetRef ref, Map? user) {
    final nameCtrl =
        TextEditingController(text: user?['name'] as String? ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Mon profil',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller:
                  TextEditingController(text: user?['email'] as String? ?? ''),
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  await buildDio()
                      .patch('/account', data: {'name': nameCtrl.text.trim()});
                  await ref.read(authProvider.notifier).refreshProfile();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Erreur lors de la mise à jour')),
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

  void _showChangePassword(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('Changer le mot de passe',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              TextFormField(
                controller: currentCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Mot de passe actuel',
                    prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Champ requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    prefixIcon: Icon(Icons.lock_reset_outlined)),
                validator: (v) =>
                    v == null || v.length < 8 ? 'Minimum 8 caractères' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: Icon(Icons.lock_reset_outlined)),
                validator: (v) => v != newCtrl.text
                    ? 'Les mots de passe ne correspondent pas'
                    : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  try {
                    await buildDio().post('/auth/change-password', data: {
                      'current_password': currentCtrl.text,
                      'password': newCtrl.text,
                      'password_confirmation': confirmCtrl.text,
                    });
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Mot de passe modifié avec succès')),
                      );
                    }
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Mot de passe actuel incorrect')),
                      );
                    }
                  }
                },
                child: const Text('Modifier'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Langue',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _LangOption(
                flag: '🇫🇷',
                label: 'Français',
                selected: true,
                onTap: () => Navigator.pop(ctx)),
            _LangOption(
                flag: '🇬🇧',
                label: 'English',
                selected: false,
                onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Synovox',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text('S',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800)),
        ),
      ),
      children: const [
        Text('Application de gestion d\'assistant téléphonique IA.'),
        SizedBox(height: 8),
        Text('© 2025 Synovox. Tous droits réservés.'),
      ],
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Se déconnecter',
                style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }
}

// ── Notifications section ──────────────────────────────────────────────────────

class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notifPrefsProvider);

    return async.when(
      loading: () => const _NotifSkeleton(),
      error: (_, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('Impossible de charger les préférences',
                    style: TextStyle(fontSize: 13))),
            TextButton(
              onPressed: () => ref.read(notifPrefsProvider.notifier).refresh(),
              child: const Text('Réessayer'),
            ),
          ]),
        ),
      ),
      data: (prefs) => Column(children: [
        // ── Appels ────────────────────────────────────────
        _NotifGroup(
          icon: Icons.phone_in_talk_rounded,
          label: 'Appels',
          color: const Color(0xFF2563EB),
          children: [
            _NotifRow(
              label: 'Nouveau appel entrant',
              subtitle: 'Chaque fois qu\'un appel arrive',
              value: prefs.newCall,
              onChanged: (_) =>
                  ref.read(notifPrefsProvider.notifier).toggle('newCall'),
            ),
            _NotifRow(
              label: 'Appel manqué',
              subtitle: 'Si l\'assistant n\'a pas pu répondre',
              value: prefs.missedCall,
              onChanged: (_) =>
                  ref.read(notifPrefsProvider.notifier).toggle('missedCall'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Rendez-vous ───────────────────────────────────
        _NotifGroup(
          icon: Icons.calendar_today_rounded,
          label: 'Rendez-vous',
          color: const Color(0xFF059669),
          children: [
            _NotifRow(
              label: 'Rappel avant RDV',
              subtitle: 'Notification ${prefs.reminderMinutesBefore} min avant',
              value: prefs.appointmentReminder,
              onChanged: (_) => ref
                  .read(notifPrefsProvider.notifier)
                  .toggle('appointmentReminder'),
              trailing: prefs.appointmentReminder
                  ? _ReminderPicker(
                      value: prefs.reminderMinutesBefore,
                      onChanged: (v) => ref
                          .read(notifPrefsProvider.notifier)
                          .setReminderMinutes(v),
                    )
                  : null,
            ),
            _NotifRow(
              label: 'RDV confirmé',
              subtitle: 'Quand un RDV est confirmé',
              value: prefs.appointmentConfirmed,
              onChanged: (_) => ref
                  .read(notifPrefsProvider.notifier)
                  .toggle('appointmentConfirmed'),
            ),
            _NotifRow(
              label: 'RDV annulé',
              subtitle: 'Quand un RDV est annulé',
              value: prefs.appointmentCancelled,
              onChanged: (_) => ref
                  .read(notifPrefsProvider.notifier)
                  .toggle('appointmentCancelled'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Assistant ─────────────────────────────────────
        _NotifGroup(
          icon: Icons.smart_toy_rounded,
          label: 'Assistant',
          color: const Color(0xFF7C3AED),
          children: [
            _NotifRow(
              label: 'Changement de statut',
              subtitle: 'Si l\'assistant passe hors ligne',
              value: prefs.assistantStatusChange,
              onChanged: (_) => ref
                  .read(notifPrefsProvider.notifier)
                  .toggle('assistantStatusChange'),
            ),
            _NotifRow(
              label: 'Résumé quotidien',
              subtitle: 'Bilan des appels chaque soir',
              value: prefs.dailySummary,
              onChanged: (_) =>
                  ref.read(notifPrefsProvider.notifier).toggle('dailySummary'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── All off shortcut ──────────────────────────────
        if (prefs.newCall ||
            prefs.missedCall ||
            prefs.appointmentReminder ||
            prefs.assistantStatusChange)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.notifications_off_outlined, size: 14),
              label: const Text('Tout désactiver',
                  style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () async {
                final off = const NotifPrefs(
                  newCall: false,
                  missedCall: false,
                  appointmentReminder: false,
                  appointmentConfirmed: false,
                  appointmentCancelled: false,
                  assistantStatusChange: false,
                  dailySummary: false,
                );
                await ref.read(notifPrefsProvider.notifier).update(off);
              },
            ),
          ),
      ]),
    );
  }
}

class _NotifGroup extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final List<Widget> children;
  const _NotifGroup({
    required this.icon,
    required this.label,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        ...children,
      ]),
    );
  }
}

class _NotifRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailing;
  const _NotifRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF94A3B8))),
            if (trailing != null) ...[
              const SizedBox(height: 6),
              trailing!,
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF2563EB),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }
}

class _ReminderPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _ReminderPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [15, 30, 60, 120, 1440];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((m) {
          final selected = m == value;
          final label = m < 60
              ? '${m}min'
              : m < 1440
                  ? '${m ~/ 60}h'
                  : '1j';
          return GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : const Color(0xFF64748B),
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NotifSkeleton extends StatelessWidget {
  const _NotifSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8),
        ),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final Widget? trailing;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: color ?? const Color(0xFF475569), size: 20),
          title: Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w500,
                  fontSize: 14)),
          trailing: trailing ??
              (color == null
                  ? const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFFCBD5E1))
                  : null),
          onTap: onTap,
        ),
      );
}

class _LangOption extends StatelessWidget {
  final String flag, label;
  final bool selected;
  final VoidCallback onTap;
  const _LangOption({
    required this.flag,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Text(flag, style: const TextStyle(fontSize: 24)),
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB))
            : null,
        onTap: onTap,
      );
}
