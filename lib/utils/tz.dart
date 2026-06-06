// Europe/Zurich timezone helper — no external package needed.
// Switzerland uses CET (UTC+1) in winter and CEST (UTC+2) in summer.
// DST rules (same as all EU countries):
//   → Start: last Sunday of March at 02:00 CET (01:00 UTC)
//   → End:   last Sunday of October at 03:00 CEST (01:00 UTC)

import 'package:intl/intl.dart';

/// Convert any API timestamp string to Europe/Zurich local time.
/// Accepts ISO-8601 with Z, +00:00, +02:00, or no offset (treated as UTC).
DateTime? parseZurich(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    DateTime dt = DateTime.parse(raw);
    // DateTime.parse returns UTC if 'Z' or offset present; local otherwise.
    // Normalise to UTC first.
    final utc = dt.isUtc ? dt : dt.toUtc();
    return utcToZurich(utc);
  } catch (_) {
    return null;
  }
}

/// Shift a UTC DateTime to Europe/Zurich (handles DST automatically).
DateTime utcToZurich(DateTime utc) {
  final offset = _zurichOffsetHours(utc);
  return utc.add(Duration(hours: offset));
}

/// Return the UTC offset in hours for Europe/Zurich at a given UTC instant.
int _zurichOffsetHours(DateTime utc) {
  final y = utc.year;

  // Last Sunday of March — transition at 01:00 UTC
  final dstStart = _lastSundayOf(y, 3).add(const Duration(hours: 1));

  // Last Sunday of October — transition at 01:00 UTC
  final dstEnd = _lastSundayOf(y, 10).add(const Duration(hours: 1));

  return (utc.compareTo(dstStart) >= 0 && utc.compareTo(dstEnd) < 0) ? 2 : 1;
}

/// Returns midnight UTC on the last Sunday of [month] in [year].
DateTime _lastSundayOf(int year, int month) {
  // Start from the first day of the NEXT month and go backwards
  var d = DateTime.utc(year, month + 1, 1);
  do {
    d = d.subtract(const Duration(days: 1));
  } while (d.weekday != DateTime.sunday);
  return d;
}

// ── Formatted helpers ──────────────────────────────────────────────────────────

/// Format an API timestamp as 'dd/MM/yyyy HH:mm' in Zurich time.
String fmtDateTime(String? raw, {String fallback = '—'}) {
  final dt = parseZurich(raw);
  if (dt == null) return fallback;
  return DateFormat('dd/MM/yyyy HH:mm').format(dt);
}

/// Format an API timestamp as 'HH:mm' in Zurich time.
String fmtTime(String? raw, {String fallback = '—'}) {
  final dt = parseZurich(raw);
  if (dt == null) return fallback;
  return DateFormat('HH:mm').format(dt);
}

/// Format an API timestamp as 'dd MMM yyyy' in Zurich time.
String fmtDate(String? raw, {String fallback = '—'}) {
  final dt = parseZurich(raw);
  if (dt == null) return fallback;
  return DateFormat('dd MMM yyyy').format(dt);
}

/// Format an API timestamp as full French date: 'EEEE dd MMMM yyyy' in Zurich.
String fmtDateLong(String? raw, {String fallback = '—'}) {
  final dt = parseZurich(raw);
  if (dt == null) return fallback;
  try {
    return DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(dt);
  } catch (_) {
    return DateFormat('dd/MM/yyyy').format(dt);
  }
}

/// Format as 'dd/MM HH:mm' (compact, for dashboard lists).
String fmtCompact(String? raw, {String fallback = '—'}) {
  final dt = parseZurich(raw);
  if (dt == null) return fallback;
  return DateFormat('dd/MM HH:mm').format(dt);
}

/// Format transcript timestamp (ISO or float seconds offset).
String fmtTranscriptTs(String? raw) {
  if (raw == null) return '';
  // Try ISO
  final dt = parseZurich(raw);
  if (dt != null) return DateFormat('HH:mm:ss').format(dt);
  // Try seconds offset like "123.45"
  try {
    final secs = double.parse(raw).toInt();
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  } catch (_) {}
  return raw;
}

/// Compare an API timestamp against now (Zurich) — returns true if in the past.
bool isApptPast(String? raw) {
  if (raw == null) return false;
  final dt = parseZurich(raw);
  if (dt == null) return false;
  return dt.isBefore(utcToZurich(DateTime.now().toUtc()));
}
