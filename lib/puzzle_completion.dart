// Completion records overview:
// 1. A CompletionRecord is the permanent fact "this image at this size was
//    finished", with a count and the latest date. Unlike a progress save,
//    it is never deleted — it is what a future collection screen will show.
// 2. One record per image + size, stored next to (but separate from) the
//    progress saves in puzzle_save.dart.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefix of every completion key. [puzzleCompletionKey] builds on it and
/// [parsePuzzleCompletionKey] strips it, so the key format lives in this
/// file only.
const puzzleCompletionKeyPrefix = 'done.';

/// Key under which a puzzle's completion record is stored.
String puzzleCompletionKey({
  required String imageId,
  required int columns,
  required int rows,
}) => '$puzzleCompletionKeyPrefix$imageId.${columns}x$rows';

/// Greedy image id, so the grid suffix anchors at the key's LAST dot (ids
/// are dot-free today, but a foreign dot must not shift the grid). Grid
/// digits are capped at 4 so an overflow-length run is rejected the same
/// way on every platform (web ints would parse it instead of overflowing).
final _completionKeyPattern = RegExp(r'^(.+)\.(\d{1,4})x(\d{1,4})$');

/// The image and grid a completion key was built for, or null for keys that
/// do not follow the [puzzleCompletionKey] format.
({String imageId, int columns, int rows})? parsePuzzleCompletionKey(
  String key,
) {
  if (!key.startsWith(puzzleCompletionKeyPrefix)) {
    return null;
  }
  final match = _completionKeyPattern.firstMatch(
    key.substring(puzzleCompletionKeyPrefix.length),
  );
  if (match == null) {
    return null;
  }
  // The 4-digit cap above makes these parses safe on VM and web alike.
  return (
    imageId: match.group(1)!,
    columns: int.parse(match.group(2)!),
    rows: int.parse(match.group(3)!),
  );
}

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

  /// Keys of every stored completion record, in no particular order.
  Future<List<String>> listCompletedKeys();
}

/// The one shared way to ask "was this image finished at this grid?" —
/// callers must not pair [puzzleCompletionKey] with [isCompleted] by hand,
/// or the sites drift apart when the key format changes.
extension PuzzleCompletionQuery on PuzzleCompletionStore {
  Future<bool> isCompletedForGrid({
    required String imageId,
    required int columns,
    required int rows,
  }) =>
      isCompleted(puzzleCompletionKey(imageId: imageId, columns: columns, rows: rows));
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
    // Parse, not just containsKey: a corrupt record must read the same
    // "never completed" on every surface (badges, sheet, Finished wall).
    return await record(key) != null;
  }

  @override
  Future<List<String>> listCompletedKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs
          .getKeys()
          .where((key) => key.startsWith(puzzleCompletionKeyPrefix))
          .toList();
    } on Object catch (error) {
      _logFailure('list', '$puzzleCompletionKeyPrefix*', error);
      return const [];
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
  Future<bool> isCompleted(String key) async => await record(key) != null;

  @override
  Future<List<String>> listCompletedKeys() async => _entries.keys
      .where((key) => key.startsWith(puzzleCompletionKeyPrefix))
      .toList();
}
