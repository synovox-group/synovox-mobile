import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_client.dart';

// ── Model ──────────────────────────────────────────────────────────────────────

class NotifPrefs {
  final bool newCall;
  final bool missedCall;
  final bool appointmentReminder;
  final bool appointmentConfirmed;
  final bool appointmentCancelled;
  final bool assistantStatusChange;
  final bool dailySummary;
  final int reminderMinutesBefore;

  const NotifPrefs({
    this.newCall = true,
    this.missedCall = true,
    this.appointmentReminder = true,
    this.appointmentConfirmed = true,
    this.appointmentCancelled = true,
    this.assistantStatusChange = true,
    this.dailySummary = false,
    this.reminderMinutesBefore = 30,
  });

  NotifPrefs copyWith({
    bool? newCall,
    bool? missedCall,
    bool? appointmentReminder,
    bool? appointmentConfirmed,
    bool? appointmentCancelled,
    bool? assistantStatusChange,
    bool? dailySummary,
    int? reminderMinutesBefore,
  }) =>
      NotifPrefs(
        newCall: newCall ?? this.newCall,
        missedCall: missedCall ?? this.missedCall,
        appointmentReminder: appointmentReminder ?? this.appointmentReminder,
        appointmentConfirmed: appointmentConfirmed ?? this.appointmentConfirmed,
        appointmentCancelled: appointmentCancelled ?? this.appointmentCancelled,
        assistantStatusChange:
            assistantStatusChange ?? this.assistantStatusChange,
        dailySummary: dailySummary ?? this.dailySummary,
        reminderMinutesBefore:
            reminderMinutesBefore ?? this.reminderMinutesBefore,
      );

  Map<String, dynamic> toJson() => {
        'new_call': newCall,
        'missed_call': missedCall,
        'appointment_reminder': appointmentReminder,
        'appointment_confirmed': appointmentConfirmed,
        'appointment_cancelled': appointmentCancelled,
        'assistant_status_change': assistantStatusChange,
        'daily_summary': dailySummary,
        'reminder_minutes_before': reminderMinutesBefore,
      };

  factory NotifPrefs.fromJson(Map<String, dynamic> j) => NotifPrefs(
        newCall: j['new_call'] as bool? ?? true,
        missedCall: j['missed_call'] as bool? ?? true,
        appointmentReminder: j['appointment_reminder'] as bool? ?? true,
        appointmentConfirmed: j['appointment_confirmed'] as bool? ?? true,
        appointmentCancelled: j['appointment_cancelled'] as bool? ?? true,
        assistantStatusChange: j['assistant_status_change'] as bool? ?? true,
        dailySummary: j['daily_summary'] as bool? ?? false,
        reminderMinutesBefore: j['reminder_minutes_before'] as int? ?? 30,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────────

class NotifPrefsNotifier extends StateNotifier<AsyncValue<NotifPrefs>> {
  NotifPrefsNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  static const _storage = FlutterSecureStorage();
  static const _cacheKey = 'notif_prefs_cache';

  Future<void> _load() async {
    // 1. Serve cached version immediately for instant UI
    final cached = await _storage.read(key: _cacheKey);
    if (cached != null) {
      try {
        state = AsyncValue.data(
            NotifPrefs.fromJson(jsonDecode(cached) as Map<String, dynamic>));
      } catch (_) {}
    }

    // 2. Fetch fresh from API
    try {
      final res = await buildDio().get('/notifications/preferences');
      final data = res.data['data'] as Map<String, dynamic>? ??
          res.data as Map<String, dynamic>? ??
          {};
      final prefs = NotifPrefs.fromJson(data);
      state = AsyncValue.data(prefs);
      await _storage.write(key: _cacheKey, value: jsonEncode(prefs.toJson()));
    } catch (_) {
      // Keep cached or use defaults
      if (state is AsyncLoading) {
        state = const AsyncValue.data(NotifPrefs());
      }
    }
  }

  Future<void> update(NotifPrefs updated) async {
    final previous = state;
    state = AsyncValue.data(updated);
    // Persist locally immediately
    await _storage.write(
        key: _cacheKey, value: jsonEncode(updated.toJson()));
    // Sync to API
    try {
      await buildDio()
          .patch('/notifications/preferences', data: updated.toJson());
    } catch (_) {
      // Silently keep local change — will sync on next session
    }
  }

  Future<void> toggle(String key) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = switch (key) {
      'newCall' => current.copyWith(newCall: !current.newCall),
      'missedCall' => current.copyWith(missedCall: !current.missedCall),
      'appointmentReminder' =>
        current.copyWith(appointmentReminder: !current.appointmentReminder),
      'appointmentConfirmed' =>
        current.copyWith(appointmentConfirmed: !current.appointmentConfirmed),
      'appointmentCancelled' =>
        current.copyWith(appointmentCancelled: !current.appointmentCancelled),
      'assistantStatusChange' =>
        current.copyWith(assistantStatusChange: !current.assistantStatusChange),
      'dailySummary' =>
        current.copyWith(dailySummary: !current.dailySummary),
      _ => current,
    };
    await update(updated);
  }

  Future<void> setReminderMinutes(int minutes) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await update(current.copyWith(reminderMinutesBefore: minutes));
  }

  void refresh() => _load();
}

final notifPrefsProvider =
    StateNotifierProvider<NotifPrefsNotifier, AsyncValue<NotifPrefs>>(
  (ref) => NotifPrefsNotifier(),
);
