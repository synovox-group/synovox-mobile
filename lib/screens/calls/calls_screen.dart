import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_client.dart';
import '../../utils/tz.dart';

// ── Pagination state ───────────────────────────────────────────────────────────

class _CallsState {
  final List items;
  final int currentPage;
  final int lastPage;
  final bool loadingMore;
  const _CallsState({
    this.items = const [],
    this.currentPage = 0,
    this.lastPage = 1,
    this.loadingMore = false,
  });
  bool get hasMore => currentPage < lastPage;
  _CallsState copyWith({List? items, int? currentPage, int? lastPage, bool? loadingMore}) =>
      _CallsState(
        items: items ?? this.items,
        currentPage: currentPage ?? this.currentPage,
        lastPage: lastPage ?? this.lastPage,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class _CallsNotifier extends AutoDisposeAsyncNotifier<_CallsState> {
  static const _perPage = 20;

  @override
  Future<_CallsState> build() => _fetchPage(1, existing: []);

  Future<_CallsState> _fetchPage(int page, {required List existing}) async {
    final res = await buildDio().get('/calls', queryParameters: {
      'page': page,
      'per_page': _perPage,
    });
    final body = res.data;
    final data = (body['data'] as List?) ?? [];
    final meta = body['meta'] as Map? ?? body;
    final lastPage = (meta['last_page'] ?? meta['total_pages'] ?? 1) as int;
    return _CallsState(
      items: [...existing, ...data],
      currentPage: page,
      lastPage: lastPage,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _fetchPage(current.currentPage + 1, existing: current.items);
      state = AsyncData(next);
    } catch (e) {
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPage(1, existing: []));
  }
}

final callsNotifierProvider =
    AsyncNotifierProvider.autoDispose<_CallsNotifier, _CallsState>(
        _CallsNotifier.new);

enum CallFilter { all, completed, missed, inProgress }

final callFilterProvider = StateProvider<CallFilter>((ref) => CallFilter.all);
final callSearchProvider = StateProvider<String>((ref) => '');

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});
  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(callsNotifierProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callsAsync = ref.watch(callsNotifierProvider);
    final filter = ref.watch(callFilterProvider);
    final search = ref.watch(callSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appels'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher un numéro...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(callSearchProvider.notifier).state = '';
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => ref.read(callSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _FilterChip(label: 'Tous', filter: CallFilter.all, current: filter),
                const SizedBox(width: 8),
                _FilterChip(label: 'Terminés', filter: CallFilter.completed, current: filter),
                const SizedBox(width: 8),
                _FilterChip(label: 'Manqués', filter: CallFilter.missed, current: filter),
                const SizedBox(width: 8),
                _FilterChip(label: 'En cours', filter: CallFilter.inProgress, current: filter),
              ],
            ),
          ),
          Expanded(
            child: callsAsync.when(
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
                      onPressed: () =>
                          ref.read(callsNotifierProvider.notifier).refresh(),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (state) {
                final filtered = _filterCalls(state.items, filter, search);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_missed_rounded,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          search.isNotEmpty
                              ? 'Aucun résultat pour "$search"'
                              : 'Aucun appel',
                          style: const TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(callsNotifierProvider.notifier).refresh(),
                  child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i == filtered.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return _CallTile(call: filtered[i]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List _filterCalls(List list, CallFilter filter, String search) {
    return list.where((c) {
      final s = (c['status'] ?? c['call_status'] ?? c['state'] ?? '').toString().toLowerCase();
      if (filter == CallFilter.completed) {
        if (!const {'completed', 'done', 'ended', 'finished'}.contains(s)) return false;
      }
      if (filter == CallFilter.missed) {
        if (!const {'missed', 'no_answer', 'voicemail'}.contains(s)) return false;
      }
      if (filter == CallFilter.inProgress) {
        if (!const {'in_progress', 'ongoing', 'active', 'ringing'}.contains(s)) return false;
      }
      if (search.isNotEmpty) {
        final number = (c['caller_number'] ?? c['from_number'] ?? c['phone_number'] ?? '').toString().toLowerCase();
        final contact = (c['contact']?['name'] ?? c['contact_name'] ?? '').toString().toLowerCase();
        if (!number.contains(search.toLowerCase()) && !contact.contains(search.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}

class _FilterChip extends ConsumerWidget {
  final String label;
  final CallFilter filter;
  final CallFilter current;
  const _FilterChip({required this.label, required this.filter, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = filter == current;
    return GestureDetector(
      onTap: () => ref.read(callFilterProvider.notifier).state = filter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
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

class _CallTile extends StatelessWidget {
  final Map call;
  const _CallTile({required this.call});

  @override
  Widget build(BuildContext context) {
    final status = call['status'] as String? ?? '';
    final isCompleted = status == 'completed';
    final isMissed = status == 'missed';

    final color = isCompleted
        ? const Color(0xFF059669)
        : isMissed
            ? const Color(0xFFDC2626)
            : const Color(0xFF2563EB);

    final icon = isCompleted
        ? Icons.phone_rounded
        : isMissed
            ? Icons.phone_missed_rounded
            : Icons.phone_in_talk_rounded;

    final dateStr = fmtDateTime(
      call['started_at'] as String? ?? call['start_time'] as String?,
      fallback: '',
    );

    final seconds = call['duration_seconds'] as int? ?? 0;
    final duration = _formatDuration(seconds);

    final summary = call['summary'] as String?
        ?? call['ai_summary'] as String?
        ?? call['transcript_summary'] as String?
        ?? call['call_summary'] as String?
        ?? call['notes'] as String?;

    final callerNumber = call['caller_number'] as String?
        ?? call['from_number'] as String?
        ?? call['phone_number'] as String?
        ?? '—';

    final contactName = (call['contact'] as Map?)?['name'] as String?
        ?? call['contact_name'] as String?;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/calls/${call['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contactName ?? callerNumber,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _StatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contactName != null
                          ? '$callerNumber · $dateStr · $duration'
                          : '$dateStr · $duration',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                    if (summary != null && summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 12, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              summary,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7C3AED),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFCBD5E1), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '—';
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m${s.toString().padLeft(2, '0')}s';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'completed' => ('Terminé', const Color(0xFF059669)),
      'missed' => ('Manqué', const Color(0xFFDC2626)),
      'in_progress' => ('En cours', const Color(0xFF2563EB)),
      _ => ('—', const Color(0xFF94A3B8)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
