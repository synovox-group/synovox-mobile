import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_client.dart';
import '../../utils/tz.dart';

// ── Providers ──────────────────────────────────────────────────────────────────

final callDetailProvider = FutureProvider.family<Map, int>((ref, id) async {
  final res = await buildDio().get('/calls/$id',
      queryParameters: {'include': 'messages,transcript,contact,phone_number'});
  final raw = res.data;
  if (raw is Map) return raw['data'] as Map? ?? Map<String, dynamic>.from(raw);
  return {};
});

/// Extract a confidence percentage (0–100) from call data, or null if absent.
int? _parseConfidence(Map data) {
  for (final key in ['confidence', 'confidence_score', 'transcription_confidence',
                     'call_confidence', 'score']) {
    final v = data[key];
    if (v == null) continue;
    if (v is num) {
      // Accept both 0.95 and 95
      return (v <= 1.0 ? (v * 100).round() : v.round());
    }
    if (v is String) {
      final n = num.tryParse(v.replaceAll('%', '').trim());
      if (n != null) return (n <= 1.0 ? (n * 100).round() : n.round());
    }
  }
  return null;
}

final callTranscriptProvider =
    FutureProvider.family<List<_TEntry>, int>((ref, id) async {
  final dio = buildDio();

  Future<List<_TEntry>?> tryGet(String path,
      {Map<String, dynamic>? params}) async {
    try {
      final res = await dio.get(path,
          queryParameters: (params?.isNotEmpty == true) ? params : null);
      final entries = _extractEntries(res.data);
      if (entries.isNotEmpty) return entries;
    } catch (_) {}
    return null;
  }

  // 1. Dedicated transcript/messages endpoints (most likely)
  for (final path in [
    '/calls/$id/transcript',
    '/calls/$id/messages',
    '/calls/$id/conversation',
    '/transcripts/$id',
  ]) {
    final r = await tryGet(path);
    if (r != null) return r;
  }

  // 2. Transcript via query param
  for (final params in [
    <String, dynamic>{'call_id': id},
    <String, dynamic>{'call_id': id, 'per_page': 500},
  ]) {
    for (final path in ['/transcripts', '/messages', '/call-messages']) {
      final r = await tryGet(path, params: params);
      if (r != null) return r;
    }
  }

  // 3. Inline include fallbacks
  for (final p in [
    <String, dynamic>{'include': 'transcript,messages,conversation'},
    <String, dynamic>{'with': 'messages'},
    <String, dynamic>{'expand': 'transcript'},
  ]) {
    final r = await tryGet('/calls/$id', params: p);
    if (r != null) return r;
  }

  return [];
});

/// All field names we probe for transcript content, in priority order.
const _txFields = [
  'messages', 'transcript', 'transcription', 'conversation', 'turns',
  'call_transcript', 'full_transcript', 'transcript_text', 'dialogue',
  'transcript_object', 'transcript_with_tool_calls',
];

/// Extract transcript entries from a raw API response body (any structure)
List<_TEntry> _extractEntries(dynamic body) {
  if (body == null) return [];
  if (body is List) return _parseTEntries(body);
  if (body is! Map) return [];

  // Standard wrapper: {data: [...]}
  final d = body['data'];
  if (d is List && d.isNotEmpty) return _parseTEntries(d);
  // Nested data map — recurse into it
  if (d is Map && d.isNotEmpty) {
    final inner = _extractFromCallData(d);
    if (inner.isNotEmpty) return inner;
  }

  // Direct fields on the response root
  final direct = _extractFromCallData(body as Map);
  if (direct.isNotEmpty) return direct;

  return [];
}

/// Extract transcript from a call detail map (handles any known API format)
List<_TEntry> _extractFromCallData(Map data) {
  // All known field names
  for (final key in _txFields) {
    final v = data[key];
    if (v is List && v.isNotEmpty) return _parseTEntries(v);
    if (v is String && v.trim().isNotEmpty) return _parseStringTranscript(v);
  }

  // VAPI: artifact.messages / artifact.transcript
  final artifact = data['artifact'] as Map?;
  if (artifact != null) {
    final msgs = artifact['messages'];
    if (msgs is List && msgs.isNotEmpty) return _parseTEntries(msgs);
    final tx = artifact['transcript'];
    if (tx is String && tx.trim().isNotEmpty) return _parseStringTranscript(tx);
  }

  // Last resort: scan ALL string values that look like multi-line transcripts
  for (final v in data.values) {
    if (v is String && v.contains('\n') && v.length > 30) {
      final entries = _parseStringTranscript(v);
      if (entries.isNotEmpty) return entries;
    }
  }

  return [];
}

/// Parse a list of message objects — handles many field naming conventions
List<_TEntry> _parseTEntries(List raw) {
  final results = <_TEntry>[];
  for (final e in raw) {
    if (e is! Map) {
      results.add(_TEntry(speaker: 'unknown', text: '$e'));
      continue;
    }

    // Speaker identification — try all common field names
    final role = (e['role']
            ?? e['speaker']
            ?? e['type']
            ?? e['from']
            ?? e['author']
            ?? 'unknown') as String;

    // Message text — try all common field names
    final text = (e['text']
            ?? e['content']
            ?? e['message']
            ?? e['body']
            ?? e['transcript']
            ?? '') as String;

    if (text.isEmpty) continue;

    final ts = e['timestamp'] as String?
        ?? e['time'] as String?
        ?? e['started_at'] as String?
        ?? e['created_at'] as String?;

    final dur = (e['duration'] ?? e['duration_seconds'] ?? e['end_time']) as int?;

    results.add(_TEntry(speaker: role, text: text, timestamp: ts, duration: dur));
  }
  return results;
}

/// Parse plain-text transcript like "Agent: ...\nUser: ..." or "Client : ..."
List<_TEntry> _parseStringTranscript(String raw) {
  final lines = raw
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final results = <_TEntry>[];
  String currentRole = 'unknown';
  final buffer = StringBuffer();

  void flush() {
    final t = buffer.toString().trim();
    if (t.isNotEmpty) {
      results.add(_TEntry(speaker: currentRole, text: t));
    }
    buffer.clear();
  }

  final rolePattern = RegExp(
      r'^(agent|assistant|bot|ai|system|user|human|caller|customer|client)\s*:\s*',
      caseSensitive: false);

  for (final line in lines) {
    final match = rolePattern.firstMatch(line);
    if (match != null) {
      flush();
      currentRole = match.group(1)!.toLowerCase();
      buffer.write(line.substring(match.end).trim());
    } else {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(line.trim());
    }
  }
  flush();

  // If no role markers found, each line is a turn alternating agent/user
  if (results.isEmpty) {
    for (var i = 0; i < lines.length; i++) {
      results.add(_TEntry(
        speaker: i.isEven ? 'agent' : 'user',
        text: lines[i].trim(),
      ));
    }
  }

  return results;
}

class _TEntry {
  final String speaker;
  final String text;
  final String? timestamp;
  final int? duration;

  const _TEntry({
    required this.speaker,
    required this.text,
    this.timestamp,
    this.duration,
  });

  bool get isAgent => const {
        'agent', 'assistant', 'bot', 'ai', 'system', 'machine'
      }.contains(speaker.toLowerCase());
}

// ── Main screen ────────────────────────────────────────────────────────────────

class CallDetailScreen extends ConsumerWidget {
  final int callId;
  const CallDetailScreen({super.key, required this.callId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callDetailProvider(callId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail appel'),
        actions: [
          call.whenOrNull(
            data: (data) => IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copier le numéro',
              onPressed: () {
                final number = data['caller_number'] as String? ?? '';
                Clipboard.setData(ClipboardData(text: number));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Numéro copié'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: call.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('Impossible de charger cet appel'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(callDetailProvider(callId)),
              child: const Text('Réessayer'),
            ),
          ]),
        ),
        data: (data) => _CallDetailBody(callId: callId, data: data),
      ),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _CallDetailBody extends ConsumerWidget {
  final int callId;
  final Map data;
  const _CallDetailBody({required this.callId, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Status — try multiple field names
    final status = (data['status']
            ?? data['call_status']
            ?? data['state']
            ?? '') as String;

    // Caller number
    final number = data['caller_number'] as String?
        ?? data['from_number'] as String?
        ?? data['phone_number'] as String?
        ?? data['caller'] as String?
        ?? '—';

    // Duration
    final seconds = (data['duration_seconds']
            ?? data['duration']
            ?? data['call_duration']
            ?? 0) as int;

    // Date — converted to Europe/Zurich
    final dateStr = fmtDateTime(
      data['started_at'] as String?
          ?? data['start_time'] as String?
          ?? data['created_at'] as String?
          ?? data['call_date'] as String?,
    );

    // Contact name if linked
    final contactMap = data['contact'] as Map?;
    final contactName = contactMap?['name'] as String?
        ?? contactMap?['full_name'] as String?
        ?? data['contact_name'] as String?;

    final (statusLabel, statusColor) = _parseCallStatus(status);
    final color = statusColor;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Caller header ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: color.withValues(alpha: 0.1),
              child: contactName != null
                  ? Text(
                      contactName[0].toUpperCase(),
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: color),
                    )
                  : Icon(Icons.person_rounded, color: color, size: 30),
            ),
            const SizedBox(height: 10),
            if (contactName != null) ...[
              Text(contactName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(number,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF64748B))),
            ] else
              Text(number,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _StatusChip(label: statusLabel, color: statusColor),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.phone_rounded, size: 18),
                label: const Text('Rappeler'),
                onPressed: () async {
                  final tel = number == '—' ? '' : number;
                  final uri = Uri(scheme: 'tel', path: tel);
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFF2563EB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Metrics ───────────────────────────────────────────
        Row(children: [
          Expanded(
            child: _MetricTile(
              icon: Icons.access_time_rounded,
              label: 'Durée',
              value: _fmtDuration(seconds),
              color: const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricTile(
              icon: Icons.calendar_today_rounded,
              label: 'Date',
              value: dateStr,
              color: const Color(0xFF7C3AED),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // ── AI Summary ─────────────────────────────────────────
        if (_notEmpty(data['summary_text'] ?? data['summary'])) ...[
          const _SectionHeader(
              title: 'Résumé IA', icon: Icons.auto_awesome_rounded),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: Color(0xFF2563EB)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${data['summary_text'] ?? data['summary']}',
                  style: const TextStyle(
                      fontSize: 14, height: 1.7, color: Color(0xFF0F172A)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // ── Appointment ────────────────────────────────────────
        if (data['appointment'] is Map) ...[
          _AppointmentCard(appt: data['appointment'] as Map),
          const SizedBox(height: 16),
        ],

        // ── Call info ──────────────────────────────────────────
        _CallInfoCard(data: data),
        const SizedBox(height: 16),

        // ── AI Tags ────────────────────────────────────────────
        if (_notEmpty(data['intent']) || _notEmpty(data['sentiment'])) ...[
          const _SectionHeader(
              title: 'Analyse IA', icon: Icons.psychology_rounded),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_notEmpty(data['intent']))
              _Tag(
                label: '${data['intent']}',
                icon: Icons.flag_rounded,
                color: const Color(0xFF7C3AED),
              ),
            if (_notEmpty(data['sentiment']))
              _Tag(
                label: _sentimentLabel(data['sentiment']),
                icon: _sentimentIcon(data['sentiment']),
                color: _sentimentColor(data['sentiment']),
              ),
          ]),
          const SizedBox(height: 16),
        ],

        // ── Transcript ─────────────────────────────────────────
        _TranscriptSection(
          callId: callId,
          transcriptStatus: data['transcript_status'] as String?,
          confidence: _parseConfidence(data),
        ),
      ],
    );
  }

  bool _notEmpty(dynamic v) => v != null && '$v'.trim().isNotEmpty;

  String _fmtDuration(int s) {
    if (s == 0) return '—';
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return '${m}m${sec}s';
  }

  (String, Color) _parseCallStatus(String s) => switch (s.toLowerCase()) {
        'completed' || 'done' || 'ended' || 'finished' => (
          'Appel terminé',
          const Color(0xFF059669)
        ),
        'missed' || 'no_answer' || 'voicemail' => (
          'Appel manqué',
          const Color(0xFFDC2626)
        ),
        'in_progress' || 'ongoing' || 'active' || 'ringing' => (
          'En cours',
          const Color(0xFF2563EB)
        ),
        'failed' || 'busy' || 'error' => ('Échec', const Color(0xFFDC2626)),
        _ => ('Appel', const Color(0xFF64748B)),
      };

  String _sentimentLabel(dynamic s) => switch ('$s'.toLowerCase()) {
        'positive' => 'Positif',
        'negative' => 'Négatif',
        'neutral' => 'Neutre',
        _ => '$s',
      };

  IconData _sentimentIcon(dynamic s) => switch ('$s'.toLowerCase()) {
        'positive' => Icons.sentiment_satisfied_rounded,
        'negative' => Icons.sentiment_dissatisfied_rounded,
        _ => Icons.sentiment_neutral_rounded,
      };

  Color _sentimentColor(dynamic s) => switch ('$s'.toLowerCase()) {
        'positive' => const Color(0xFF059669),
        'negative' => const Color(0xFFDC2626),
        _ => const Color(0xFF64748B),
      };
}

// ── Transcript section ─────────────────────────────────────────────────────────

class _TranscriptSection extends ConsumerStatefulWidget {
  final int callId;
  final int? confidence;
  final String? transcriptStatus;
  const _TranscriptSection({
    required this.callId,
    this.confidence,
    this.transcriptStatus,
  });

  @override
  ConsumerState<_TranscriptSection> createState() => _TranscriptSectionState();
}

class _TranscriptSectionState extends ConsumerState<_TranscriptSection> {
  String _query = '';
  bool _showSearch = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(callTranscriptProvider(widget.callId));

    return async.when(
      loading: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _transcriptHeader(null),
        const SizedBox(height: 12),
        const _TranscriptSkeleton(),
      ]),
      error: (_, __) => _EmptyTranscript(
        onRetry: () => ref.invalidate(callTranscriptProvider(widget.callId)),
        transcriptStatus: widget.transcriptStatus,
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return _EmptyTranscript(
            onRetry: () => ref.invalidate(callTranscriptProvider(widget.callId)),
            transcriptStatus: widget.transcriptStatus,
          );
        }

        final filtered = _query.isEmpty
            ? entries
            : entries
                .where((e) =>
                    e.text.toLowerCase().contains(_query.toLowerCase()))
                .toList();

        final agentCount = entries.where((e) => e.isAgent).length;
        final callerCount = entries.length - agentCount;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _transcriptHeader(entries),
          const SizedBox(height: 10),

          // Stats chips
          Wrap(spacing: 8, runSpacing: 6, children: [
            _MiniChip(
              label: 'Assistant: $agentCount',
              color: const Color(0xFF2563EB),
              icon: Icons.smart_toy_outlined,
            ),
            _MiniChip(
              label: 'Appelant: $callerCount',
              color: const Color(0xFF7C3AED),
              icon: Icons.person_outline_rounded,
            ),
            if (widget.confidence != null)
              _MiniChip(
                label: 'Confiance : ${widget.confidence}%',
                color: widget.confidence! >= 80
                    ? const Color(0xFF059669)
                    : widget.confidence! >= 60
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFDC2626),
                icon: Icons.verified_rounded,
              ),
          ]),
          const SizedBox(height: 12),

          // Search field
          if (_showSearch) ...[
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher dans la transcription…',
                hintStyle: const TextStyle(
                    fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => setState(() {
                          _query = '';
                          _searchCtrl.clear();
                        }),
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            if (_query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  '${filtered.length} résultat${filtered.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF64748B)),
                ),
              ),
            const SizedBox(height: 10),
          ],

          // Bubbles or "no result"
          if (filtered.isEmpty && _query.isNotEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Aucun résultat',
                    style: TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13)),
              ),
            )
          else
            ...filtered
                .map((e) => _TranscriptBubble(entry: e, highlight: _query)),

          const SizedBox(height: 8),
        ]);
      },
    );
  }

  Widget _transcriptHeader(List<_TEntry>? entries) {
    return Row(children: [
      const Icon(Icons.chat_bubble_outline_rounded,
          size: 16, color: Color(0xFF2563EB)),
      const SizedBox(width: 6),
      const Text('Transcription',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const Spacer(),
      if (entries != null) ...[
        Text('${entries.length} msg',
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF94A3B8))),
        const SizedBox(width: 8),
      ] else
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      if (entries != null) ...[
        _iconBtn(
          icon: _showSearch
              ? Icons.search_off_rounded
              : Icons.search_rounded,
          active: _showSearch,
          onTap: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) {
              _query = '';
              _searchCtrl.clear();
            }
          }),
        ),
        const SizedBox(width: 6),
        _iconBtn(
          icon: Icons.copy_all_rounded,
          active: false,
          onTap: () => _copyAll(entries, context),
        ),
      ],
    ]);
  }

  Widget _iconBtn({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF2563EB).withValues(alpha: 0.1)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 16,
              color: active
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF64748B)),
        ),
      );

  void _copyAll(List<_TEntry> entries, BuildContext context) {
    final buf = StringBuffer();
    for (final e in entries) {
      final who = e.isAgent ? 'Assistant' : 'Appelant';
      buf.writeln(e.timestamp != null ? '[$who – ${e.timestamp}]' : '[$who]');
      buf.writeln(e.text);
      buf.writeln();
    }
    Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Transcription copiée'),
          duration: Duration(seconds: 2)),
    );
  }
}

// ── Empty / error state ────────────────────────────────────────────────────────

class _EmptyTranscript extends StatelessWidget {
  final VoidCallback onRetry;
  final String? transcriptStatus;
  const _EmptyTranscript({required this.onRetry, this.transcriptStatus});

  @override
  Widget build(BuildContext context) {
    final isPending = transcriptStatus == null ||
        transcriptStatus == 'pending' ||
        transcriptStatus == 'processing' ||
        transcriptStatus == 'in_progress';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.chat_bubble_outline_rounded,
            size: 16, color: Color(0xFF2563EB)),
        SizedBox(width: 6),
        Text('Transcription',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isPending ? Icons.hourglass_empty_rounded : Icons.chat_bubble_outline_rounded,
            size: 36,
            color: const Color(0xFFCBD5E1),
          ),
          const SizedBox(height: 10),
          Text(
            isPending ? 'Transcription en cours…' : 'Transcription non disponible',
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            isPending
                ? 'La transcription sera disponible dans quelques instants.'
                : 'La transcription de cet appel n\'est pas disponible.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          if (!isPending) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Réessayer'),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }
}

// ── Appointment card ───────────────────────────────────────────────────────────

class _AppointmentCard extends StatelessWidget {
  final Map appt;
  const _AppointmentCard({required this.appt});

  @override
  Widget build(BuildContext context) {
    final title = appt['title'] as String?
        ?? appt['service_type'] as String?
        ?? 'Rendez-vous';
    final dateRaw = appt['appointment_date'] as String?
        ?? appt['date'] as String?
        ?? appt['scheduled_at'] as String?
        ?? appt['start_at'] as String?;
    final dateStr = dateRaw != null ? fmtDateTime(dateRaw) : null;
    final status = appt['status'] as String?;
    final notes = appt['notes'] as String? ?? appt['description'] as String?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(
          title: 'Rendez-vous pris', icon: Icons.event_available_rounded),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event_available_rounded,
                size: 20, color: Color(0xFF059669)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              if (dateStr != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.schedule_rounded,
                      size: 13, color: Color(0xFF059669)),
                  const SizedBox(width: 4),
                  Text(dateStr,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF065F46))),
                ]),
              ],
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(notes,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B), height: 1.4)),
              ],
              if (status != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _apptStatusLabel(status),
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    ]);
  }

  String _apptStatusLabel(String s) => switch (s.toLowerCase()) {
        'confirmed' || 'confirmé' => 'Confirmé',
        'pending' => 'En attente',
        'cancelled' || 'canceled' => 'Annulé',
        'completed' || 'done' => 'Terminé',
        _ => s,
      };
}

// ── Call info card ──────────────────────────────────────────────────────────────

class _CallInfoCard extends StatelessWidget {
  final Map data;
  const _CallInfoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final assistant = data['assistant'] as Map?;
    final phoneNumber = data['phone_number'] as Map?;
    final direction = data['direction'] as String?;
    final outcome = data['outcome'] as String?;
    final forwardedAi = data['forwarded_to_ai'] as bool?;
    final transferred = data['transferred_to_human'] as bool?;

    final rows = <_CInfoRow>[];
    if (assistant != null) {
      rows.add(_CInfoRow(
        icon: Icons.smart_toy_outlined,
        label: 'Assistant',
        value: assistant['name'] as String? ?? 'IA',
        color: const Color(0xFF7C3AED),
      ));
    }
    if (phoneNumber != null) {
      rows.add(_CInfoRow(
        icon: Icons.phone_rounded,
        label: 'Numéro appelé',
        value: phoneNumber['public_number'] as String?
            ?? phoneNumber['technical_number'] as String?
            ?? '—',
        color: const Color(0xFF2563EB),
      ));
    }
    if (direction != null) {
      rows.add(_CInfoRow(
        icon: direction == 'inbound'
            ? Icons.call_received_rounded
            : Icons.call_made_rounded,
        label: 'Direction',
        value: direction == 'inbound' ? 'Entrant' : 'Sortant',
        color: const Color(0xFF64748B),
      ));
    }
    if (outcome != null) {
      rows.add(_CInfoRow(
        icon: Icons.flag_rounded,
        label: 'Résultat',
        value: _outcomeLabel(outcome),
        color: const Color(0xFF64748B),
      ));
    }
    if (forwardedAi == true) {
      rows.add(const _CInfoRow(
        icon: Icons.smart_toy_rounded,
        label: 'Traité par IA',
        value: 'Oui',
        color: Color(0xFF2563EB),
      ));
    }
    if (transferred == true) {
      rows.add(const _CInfoRow(
        icon: Icons.transfer_within_a_station_rounded,
        label: 'Transféré à un humain',
        value: 'Oui',
        color: Color(0xFFF59E0B),
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(
          title: 'Informations', icon: Icons.info_outline_rounded),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: rows.asMap().entries.map((e) {
            final isLast = e.key == rows.length - 1;
            final r = e.value;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(children: [
                  Icon(r.icon, size: 16, color: r.color),
                  const SizedBox(width: 10),
                  Text(r.label,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF64748B))),
                  const Spacer(),
                  Text(r.value,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: r.color)),
                ]),
              ),
              if (!isLast)
                const Divider(
                    height: 1, indent: 42, color: Color(0xFFF1F5F9)),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  String _outcomeLabel(String s) => switch (s.toLowerCase()) {
        'completed' || 'done' => 'Terminé',
        'missed' || 'no_answer' => 'Manqué',
        'transferred' => 'Transféré',
        'failed' => 'Échoué',
        _ => s,
      };
}

class _CInfoRow {
  final IconData icon;
  final String label, value;
  final Color color;
  const _CInfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});
}

// ── Skeleton ───────────────────────────────────────────────────────────────────

class _TranscriptSkeleton extends StatelessWidget {
  const _TranscriptSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _SkeletonBubble(isLeft: true, width: 220),
      _SkeletonBubble(isLeft: false, width: 160),
      _SkeletonBubble(isLeft: true, width: 260),
      _SkeletonBubble(isLeft: false, width: 180),
      _SkeletonBubble(isLeft: true, width: 200),
    ]);
  }
}

class _SkeletonBubble extends StatelessWidget {
  final bool isLeft;
  final double width;
  const _SkeletonBubble({required this.isLeft, required this.width});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isLeft) ...[
            const CircleAvatar(
                radius: 14, backgroundColor: Color(0xFFE2E8F0)),
            const SizedBox(width: 8),
          ],
          Container(
            width: width,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          if (!isLeft) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
                radius: 14, backgroundColor: Color(0xFFE2E8F0)),
          ],
        ],
      ),
    );
  }
}

// ── Transcript bubble ──────────────────────────────────────────────────────────

class _TranscriptBubble extends StatelessWidget {
  final _TEntry entry;
  final String highlight;
  const _TranscriptBubble({required this.entry, this.highlight = ''});

  @override
  Widget build(BuildContext context) {
    final isAgent = entry.isAgent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isAgent ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAgent) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFFEFF6FF),
              child: const Icon(Icons.smart_toy_outlined,
                  size: 14, color: Color(0xFF2563EB)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isAgent ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                if (entry.timestamp != null)
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: 3, left: 4, right: 4),
                    child: Text(
                      _formatTs(entry.timestamp!),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFCBD5E1)),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isAgent
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isAgent ? 4 : 16),
                      bottomRight: Radius.circular(isAgent ? 16 : 4),
                    ),
                    border: Border.all(
                      color: isAgent
                          ? const Color(0xFFBFDBFE)
                          : const Color(0xFFE2E8F0),
                      width: 0.5,
                    ),
                  ),
                  child: _buildText(entry.text, highlight),
                ),
                if (entry.duration != null)
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Text('${entry.duration}s',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFFCBD5E1))),
                  ),
              ],
            ),
          ),
          if (!isAgent) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFFF5F3FF),
              child: const Icon(Icons.person_rounded,
                  size: 14, color: Color(0xFF7C3AED)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildText(String text, String query) {
    if (query.isEmpty) {
      return Text(text,
          style: const TextStyle(fontSize: 13, height: 1.5));
    }
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lower.indexOf(lowerQ, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start)
        spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFEF08A),
          color: Color(0xFF713F12),
          fontWeight: FontWeight.w600,
        ),
      ));
      start = idx + query.length;
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(
            fontSize: 13, height: 1.5, color: Color(0xFF0F172A)),
        children: spans,
      ),
    );
  }

  String _formatTs(String ts) => fmtTranscriptTs(ts);
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _MiniChip(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
                fontSize: 13)),
      );
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MetricTile(
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
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF94A3B8))),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
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

class _Tag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Tag(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}
