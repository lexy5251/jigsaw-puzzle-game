// Daily-streak storage overview:
// 1. Persists the set of day keys ("2026-11-02") on which the daily puzzle
//    was completed — the permanent input for the streak math in
//    daily_puzzle.dart.
// 2. One shared_preferences entry holds the whole set as a JSON list; a
//    few bytes per played day, so it never needs pruning.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads and records which days the daily puzzle was completed on.
abstract class DailyStreakStore {
  Future<Set<String>> completedDays();

  /// Returns true only when storage holds the day afterwards. Marking an
  /// already-stored day is a successful no-op.
  Future<bool> markCompleted(String dayKey);
}

/// Device-local storage. Failures are logged in debug builds and handled
/// without throwing — a streak is decoration and must never break gameplay.
class SharedPreferencesDailyStreakStore implements DailyStreakStore {
  const SharedPreferencesDailyStreakStore();

  static const _key = 'daily.days';

  @override
  Future<Set<String>> completedDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_key));
    } on Object catch (error) {
      _logFailure('read', error);
      return {};
    }
  }

  @override
  Future<bool> markCompleted(String dayKey) async {
    SharedPreferences? prefs;
    String? previous;
    // The revert below must only undo THIS call's cache update: a failure
    // before the setString (read error, wrong-typed stored value) must not
    // delete or rewrite data this call never touched.
    var wroteCache = false;
    try {
      prefs = await SharedPreferences.getInstance();
      // Re-read storage first: this method read-modify-writes the WHOLE day
      // list, and a stale cache (e.g. a second tab on web) would persist a
      // list missing days stored through another cache.
      await prefs.reload();
      previous = prefs.getString(_key);
      final days = _decode(previous);
      if (days.contains(dayKey)) {
        return true;
      }
      days.add(dayKey);
      wroteCache = true;
      final saved = await prefs.setString(_key, _encode(days));
      if (saved) {
        return true;
      }
      _logFailure('write', 'Storage returned false.');
    } on Object catch (error) {
      _logFailure('write', error);
    }

    // A failed setString still updates the in-memory preferences cache; put
    // the old value back so the streak display never shows a day that was
    // not persisted. These calls fix the cache before touching the platform,
    // so the repair holds even while storage stays unavailable.
    if (wroteCache) {
      try {
        if (previous == null) {
          await prefs?.remove(_key);
        } else {
          await prefs?.setString(_key, previous);
        }
      } on Object catch (error) {
        _logFailure('revert', error);
      }
    }
    return false;
  }

  String _encode(Set<String> days) => jsonEncode(days.toList()..sort());

  /// Malformed data reads as "no days yet" instead of crashing.
  Set<String> _decode(String? raw) {
    if (raw == null) {
      return {};
    }
    try {
      final data = jsonDecode(raw);
      if (data is! List) {
        return {};
      }
      return data.whereType<String>().toSet();
    } on Object {
      return {};
    }
  }

  void _logFailure(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('Daily streak storage: $operation failed: $error');
    }
  }
}

/// Keeps days in a plain set; used by tests.
class InMemoryDailyStreakStore implements DailyStreakStore {
  final Set<String> _days = {};

  @override
  Future<Set<String>> completedDays() async => Set.of(_days);

  @override
  Future<bool> markCompleted(String dayKey) async {
    _days.add(dayKey);
    return true;
  }
}
