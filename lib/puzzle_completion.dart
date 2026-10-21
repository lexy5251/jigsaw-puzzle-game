// Completion records overview:
// 1. A CompletionRecord is the permanent fact "this image at this size was
//    finished", with a count and the latest date. Unlike a progress save,
//    it is never deleted — it is what a future collection screen will show.
// 2. One record per image + size, stored next to (but separate from) the
//    progress saves in puzzle_save.dart.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key under which a puzzle's completion record is stored.
String puzzleCompletionKey({
  required String imageId,
  required int columns,
  required int rows,
}) => 'done.$imageId.${columns}x$rows';

/// The permanent record of finishing one puzzle.
class CompletionRecord {
  const CompletionRecord({required this.count, required this.lastCompletedAt});

  /// How many times this puzzle has been finished.
  final int count;

  final DateTime lastCompletedAt;

  String toJsonString() =>
      jsonEncode({'count': count, 'last': lastCompletedAt.toIso8601String()});

  /// Returns null when [raw] is not a valid record.
  static CompletionRecord? fromJsonString(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return CompletionRecord(
        count: data['count'] as int,
        lastCompletedAt: DateTime.parse(data['last'] as String),
      );
    } on Object {
      return null; // Malformed data: treat as "never completed".
    }
  }
}

/// Reads and writes completion records by key.
abstract class PuzzleCompletionStore {
  Future<CompletionRecord?> record(String key);

  /// Returns true only when storage accepts the completion record.
  Future<bool> markCompleted(String key, {DateTime? completedAt});
  Future<bool> isCompleted(String key);
}

/// Device-local storage. Failures are logged in debug builds and handled
/// without throwing, so a storage problem does not interrupt gameplay.
class SharedPreferencesCompletionStore implements PuzzleCompletionStore {
  const SharedPreferencesCompletionStore();

  @override
  Future<CompletionRecord?> record(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      return raw == null ? null : CompletionRecord.fromJsonString(raw);
    } on Object catch (error) {
      _logFailure('read', key, error);
      return null;
    }
  }

  @override
  Future<bool> markCompleted(String key, {DateTime? completedAt}) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      // A failed setString can still update the preferences cache. Read the
      // stored record before incrementing so a retry does not count twice.
      await prefs.reload();
      final raw = prefs.getString(key);
      final previous = raw == null
          ? null
          : CompletionRecord.fromJsonString(raw);
      final updated = CompletionRecord(
        count: (previous?.count ?? 0) + 1,
        lastCompletedAt: completedAt ?? DateTime.now(),
      );
      final saved = await prefs.setString(key, updated.toJsonString());
      if (saved) {
        return true;
      }
      _logFailure('write', key, 'Storage returned false.');
    } on Object catch (error) {
      _logFailure('write', key, error);
    }

    // Do not display a completion that only reached the in-memory cache.
    try {
      await prefs?.reload();
    } on Object catch (error) {
      _logFailure('reload', key, error);
    }
    return false;
  }

  @override
  Future<bool> isCompleted(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(key);
    } on Object catch (error) {
      _logFailure('check', key, error);
      return false;
    }
  }

  void _logFailure(String operation, String key, Object error) {
    if (kDebugMode) {
      debugPrint('Completion storage: $operation failed for "$key": $error');
    }
  }
}

/// Keeps records in a plain map; used by tests.
class InMemoryCompletionStore implements PuzzleCompletionStore {
  final Map<String, String> _entries = {};

  @override
  Future<CompletionRecord?> record(String key) async {
    final raw = _entries[key];
    return raw == null ? null : CompletionRecord.fromJsonString(raw);
  }

  @override
  Future<bool> markCompleted(String key, {DateTime? completedAt}) async {
    final previous = await record(key);
    _entries[key] = CompletionRecord(
      count: (previous?.count ?? 0) + 1,
      lastCompletedAt: completedAt ?? DateTime.now(),
    ).toJsonString();
    return true;
  }

  @override
  Future<bool> isCompleted(String key) async => _entries.containsKey(key);
}
