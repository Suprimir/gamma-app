import 'package:shared_preferences/shared_preferences.dart';

/// Cross-surface usage ranking for the 1-tap quick actions.
///
/// Wall, desktop and mobile share the same keys (e.g. `apagar`, `noche`,
/// `segura`, `fuera`), so the most-used actions rotate to the front on every
/// surface. Persisted locally via SharedPreferences; failures fall back to an
/// in-memory counter so the UI never breaks.
class WallQuickActionsUsage {
  static const _countPrefix = 'wall_quick_use_count_';
  static const _lastPrefix = 'wall_quick_use_last_';

  static final Map<String, int> _memCount = {};
  static final Map<String, int> _memLast = {};

  /// Synchronous in-memory order (no plugin I/O): safe for first paint and
  /// widget tests. Unknown keys keep their relative order at the end.
  static List<String> memoryOrder(List<String> keys) {
    final ordered = List<String>.of(keys);
    ordered.sort((a, b) {
      final countCmp = (_memCount[b] ?? 0).compareTo(_memCount[a] ?? 0);
      if (countCmp != 0) return countCmp;
      return (_memLast[b] ?? 0).compareTo(_memLast[a] ?? 0);
    });
    return ordered;
  }

  /// Returns [keys] ordered by use count (desc), then recency (desc).
  /// Unknown keys keep their relative order at the end.
  /// Never throws: any plugin failure falls back to memory. Note this future
  /// may never complete where the plugin is unavailable (widget tests); the
  /// wall home always paints first from [memoryOrder], so awaiting this must
  /// never gate first paint.
  static Future<List<String>> orderedKeys(List<String> keys) async {
    Map<String, int> counts = Map.of(_memCount);
    Map<String, int> lasts = Map.of(_memLast);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in keys) {
        counts[key] = prefs.getInt('$_countPrefix$key') ?? counts[key] ?? 0;
        lasts[key] = prefs.getInt('$_lastPrefix$key') ?? lasts[key] ?? 0;
      }
    } catch (_) {
      // Local-only fallback: in-memory counters still rotate within session.
    }
    final ordered = List<String>.of(keys);
    ordered.sort((a, b) {
      final countCmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      if (countCmp != 0) return countCmp;
      return (lasts[b] ?? 0).compareTo(lasts[a] ?? 0);
    });
    return ordered;
  }

  /// Records one execution of [key] from any surface. Memory updates apply
  /// immediately; persistence is best-effort and never awaited by callers
  /// that gate UI (same dangling-future note as [orderedKeys] in tests).
  static Future<void> recordUse(String key) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _memCount[key] = (_memCount[key] ?? 0) + 1;
    _memLast[key] = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_countPrefix$key', _memCount[key]!);
      await prefs.setInt('$_lastPrefix$key', now);
    } catch (_) {
      // Rotation still works in-memory for this session.
    }
  }
}
