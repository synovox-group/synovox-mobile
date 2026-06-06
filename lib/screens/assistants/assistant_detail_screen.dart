import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../services/app_cache.dart';
import '../assistants/assistants_screen.dart';

// Searches a map for the first non-zero int under multiple possible key names.
int _findInt(Map data, List<String> keys) {
  for (final k in keys) {
    final v = data[k];
    if (v == null) continue;
    if (v is int && v > 0) return v;
    if (v is double && v > 0) return v.toInt();
    if (v is String) { final n = int.tryParse(v); if (n != null && n > 0) return n; }
  }
  return 0;
}

final assistantDetailProvider = FutureProvider.family<Map, int>((ref, id) async {
  final dio = buildDio();

  // ── 1. Main assistant data ─────────────────────────────────────────────
  final res = await dio.get('/assistants/$id');
  final raw = res.data;
  final data = Map<String, dynamic>.from(
    raw is Map ? (raw['data'] as Map? ?? raw) : {},
  );

  debugPrint('[AssistantDetail] API keys: ${data.keys.toList()}');

  // ── 2. If stats missing, compute from calls ────────────────────────────
  final alreadyHasCalls = _findInt(data, [
    'calls_handled', 'total_calls', 'calls_count',
    'handled_calls', 'call_count',
  ]) > 0;

  if (!alreadyHasCalls) {
    try {
      // Try filtering calls by this assistant
      final callsRes = await dio.get('/calls', queryParameters: {
        'assistant_id': id,
        'per_page': 500,
      });
      final body = callsRes.data;
      final calls = body is Map
          ? (body['data'] as List? ?? [])
          : (body is List ? body : []);

      debugPrint('[AssistantDetail] calls for assistant: ${calls.length}');

      if (calls.isNotEmpty) {
        data['_calls_count'] = calls.length;

        final durations = calls
            .whereType<Map>()
            .map((c) => _findInt(c, [
                  'duration', 'duration_seconds', 'call_duration',
                  'length', 'talk_time',
                ]))
            .where((d) => d > 0)
            .toList();

        if (durations.isNotEmpty) {
          data['_avg_duration'] =
              durations.reduce((a, b) => a + b) ~/ durations.length;
        }
      }
    } catch (e) {
      debugPrint('[AssistantDetail] calls fetch error: $e');
    }
  }

  return data;
});

class AssistantDetailScreen extends ConsumerWidget {
  final int assistantId;
  const AssistantDetailScreen({super.key, required this.assistantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(assistantDetailProvider(assistantId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant IA'),
        actions: [
          data.whenOrNull(
            data: (d) => IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Modifier',
              onPressed: () => _showEditSheet(context, ref, d),
            ),
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('Impossible de charger cet assistant'),
            TextButton(
              onPressed: () => ref.invalidate(assistantDetailProvider(assistantId)),
              child: const Text('Réessayer'),
            ),
          ]),
        ),
        data: (d) => _AssistantBody(assistantId: assistantId, data: d),
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, Map data) {
    final greetingCtrl = TextEditingController(
        text: data['greeting_message'] as String? ?? '');
    final promptCtrl = TextEditingController(
        text: data['system_prompt'] as String? ?? '');
    final nameCtrl = TextEditingController(
        text: data['name'] as String? ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Modifier l\'assistant',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom de l\'assistant',
                  prefixIcon: Icon(Icons.smart_toy_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: greetingCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message d\'accueil',
                  hintText: 'Bonjour, comment puis-je vous aider ?',
                  prefixIcon: Icon(Icons.waving_hand_rounded),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: promptCtrl,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Instructions système',
                  hintText: 'Tu es un assistant téléphonique…',
                  prefixIcon: Icon(Icons.code_rounded),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await buildDio().patch('/assistants/${data['id']}', data: {
                      'name': nameCtrl.text.trim(),
                      'greeting_message': greetingCtrl.text.trim(),
                      'system_prompt': promptCtrl.text.trim(),
                    });
                    ref.invalidate(assistantDetailProvider(data['id'] as int));
                    ref.invalidate(assistantsProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Erreur lors de la sauvegarde')),
                      );
                    }
                  }
                },
                child: const Text('Enregistrer les modifications'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _AssistantBody extends ConsumerStatefulWidget {
  final int assistantId;
  final Map data;
  const _AssistantBody({required this.assistantId, required this.data});

  @override
  ConsumerState<_AssistantBody> createState() => _AssistantBodyState();
}

class _AssistantBodyState extends ConsumerState<_AssistantBody> {
  late bool _isActive;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    // null/missing → true (present = active by default, matches web)
    final raw = widget.data['is_active'] ?? widget.data['active'] ?? widget.data['status'];
    _isActive = raw == null ? true
        : raw is bool ? raw
        : raw is int ? raw != 0
        : raw is String
            ? (['1','true','active','on'].contains(raw.toString().toLowerCase()))
        : true;
    // Apply locally cached toggle (user explicitly set it in this app)
    _loadCachedActive();
  }

  Future<void> _loadCachedActive() async {
    // Only override if the API returned null (no explicit value from server)
    final apiRaw = widget.data['is_active'] ?? widget.data['active'];
    if (apiRaw != null) return; // API has a real value — trust it, not local cache
    final cached = await AppCache.loadBool('assistant_active_${widget.assistantId}');
    if (cached != null && mounted) setState(() => _isActive = cached);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final name = data['name'] as String? ?? 'Assistant';
    final language = (data['language'] as String? ?? 'fr').toUpperCase();
    final sector = data['sector'] as String? ?? 'Général';
    final phoneNumber = data['phone_number'] as String?;
    final voiceName = data['voice_name'] as String?;
    final greeting = data['greeting_message'] as String?;
    final systemPrompt = data['system_prompt'] as String?;
    final callsHandled = _findInt(data, [
      'calls_handled', 'total_calls', 'calls_count',
      'handled_calls', 'call_count', '_calls_count',
    ]);
    final avgDuration = _findInt(data, [
      'avg_duration_seconds', 'average_duration', 'avg_duration',
      'mean_duration', 'avg_call_duration', '_avg_duration',
    ]);
    final maxCallDuration = _findInt(data, [
      'max_call_duration', 'max_duration', 'maximum_duration',
    ]);
    final maxCallDurationVal = maxCallDuration > 0 ? maxCallDuration : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Header card ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: _isActive
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFEFF6FF), Color(0xFFF0FDF4)],
                  )
                : null,
            color: _isActive ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isActive
                  ? const Color(0xFF2563EB).withOpacity(0.25)
                  : const Color(0xFFE2E8F0),
              width: _isActive ? 1.5 : 1,
            ),
            boxShadow: _isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Column(children: [
            // Avatar with animated pulse when active
            Stack(alignment: Alignment.center, children: [
              if (_isActive)
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2563EB).withOpacity(0.08),
                  ),
                ),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: _isActive
                      ? const Color(0xFF2563EB).withOpacity(0.12)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: _isActive
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF94A3B8),
                  size: 34,
                ),
              ),
              if (_isActive)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Text(name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('$language · $sector',
                style:
                    const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
            const SizedBox(height: 16),

            // ── Active toggle ────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _isActive
                    ? const Color(0xFFF0FDF4)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isActive
                      ? const Color(0xFFBBF7D0)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isActive
                        ? const Color(0xFF059669)
                        : const Color(0xFFCBD5E1),
                    boxShadow: _isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF059669).withOpacity(0.5),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _isActive
                        ? const Color(0xFF059669)
                        : const Color(0xFF94A3B8),
                  ),
                  child: Text(_isActive ? 'En ligne · Actif' : 'Hors ligne · Inactif'),
                ),
                const Spacer(),
                _toggling
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _isActive,
                        onChanged: _confirmToggle,
                        activeColor: const Color(0xFF059669),
                      ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Stats ─────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: _StatTile(
              icon: Icons.call_received_rounded,
              label: 'Appels traités',
              value: callsHandled == 0 ? '0' : '$callsHandled',
              color: const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatTile(
              icon: Icons.timer_rounded,
              label: 'Durée moyenne',
              value: avgDuration == 0 ? '—' : _fmtDur(avgDuration),
              color: const Color(0xFF7C3AED),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Configuration ─────────────────────────────────────
        const _SectionHeader(title: 'Configuration', icon: Icons.settings_rounded),
        const SizedBox(height: 8),

        _ConfigCard(rows: [
          if (phoneNumber != null)
            _CRow(icon: Icons.phone_rounded, label: 'Numéro', value: phoneNumber),
          _CRow(icon: Icons.language_rounded, label: 'Langue', value: language),
          _CRow(icon: Icons.work_outline_rounded, label: 'Secteur', value: sector),
          if (voiceName != null)
            _CRow(icon: Icons.record_voice_over_rounded, label: 'Voix', value: voiceName),
          if (maxCallDurationVal != null)
            _CRow(
              icon: Icons.hourglass_bottom_rounded,
              label: 'Durée max appel',
              value: _fmtDur(maxCallDurationVal),
            ),
        ]),
        const SizedBox(height: 16),

        // ── Greeting message ──────────────────────────────────
        if (greeting != null && greeting.isNotEmpty) ...[
          const _SectionHeader(
              title: 'Message d\'accueil', icon: Icons.waving_hand_rounded),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.format_quote_rounded,
                  size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(greeting,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Color(0xFF0F172A))),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // ── System prompt ─────────────────────────────────────
        if (systemPrompt != null && systemPrompt.isNotEmpty) ...[
          Row(children: [
            const _SectionHeader(
                title: 'Instructions système', icon: Icons.code_rounded),
            const Spacer(),
            Text(
              '${systemPrompt.split(' ').length} mots',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              systemPrompt,
              style: const TextStyle(
                fontSize: 12,
                height: 1.7,
                fontFamily: 'monospace',
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── Danger zone ───────────────────────────────────────
        if (_isActive)
          OutlinedButton.icon(
            icon: const Icon(Icons.power_settings_new_rounded,
                size: 16, color: Color(0xFFDC2626)),
            label: const Text('Désactiver l\'assistant',
                style: TextStyle(color: Color(0xFFDC2626))),
            onPressed: () => _confirmToggle(false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFDC2626)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _confirmToggle(bool value) {
    if (!value && _isActive) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Désactiver l\'assistant ?'),
          content: const Text(
              'L\'assistant ne répondra plus aux appels entrants. Vous pouvez le réactiver à tout moment.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () {
                Navigator.pop(ctx);
                _doToggle(false);
              },
              child: const Text('Désactiver',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      _doToggle(value);
    }
  }

  Future<void> _doToggle(bool value) async {
    setState(() => _toggling = true);
    try {
      await buildDio()
          .patch('/assistants/${widget.assistantId}', data: {'is_active': value});
      // Persist the new state locally
      await AppCache.saveBool('assistant_active_${widget.assistantId}', value);
      setState(() => _isActive = value);
      ref.invalidate(assistantsProvider);
      ref.invalidate(assistantDetailProvider(widget.assistantId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value
                ? 'Assistant activé — en ligne'
                : 'Assistant désactivé'),
            backgroundColor:
                value ? const Color(0xFF059669) : const Color(0xFF64748B),
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
      if (mounted) setState(() => _toggling = false);
    }
  }

  String _fmtDur(int s) {
    if (s == 0) return '—';
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF2563EB)),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ]);
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _StatTile(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _CRow {
  final IconData icon;
  final String label, value;
  const _CRow({required this.icon, required this.label, required this.value});
}

class _ConfigCard extends StatelessWidget {
  final List<_CRow> rows;
  const _ConfigCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          final row = e.value;
          return Column(children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                Icon(row.icon, size: 17, color: const Color(0xFF64748B)),
                const SizedBox(width: 12),
                Text(row.label,
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 13)),
                const Spacer(),
                Text(row.value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
            ),
            if (!isLast)
              const Divider(height: 1, indent: 44, color: Color(0xFFF1F5F9)),
          ]);
        }).toList(),
      ),
    );
  }
}
