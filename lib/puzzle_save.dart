// Save & resume overview:
// 1. PuzzleSaveState is a snapshot of one puzzle in progress: which pieces
//    are locked, where loose pieces lie on the board, and the tray order.
// 2. Pieces are identified by their canonical index (row * columns + column),
//    so a snapshot stays valid across app restarts.
// 3. PuzzleSaveStore reads/writes snapshots by key. The shared_preferences
//    implementation backs the app; the in-memory one backs tests.
// 4. JigsawGame writes a snapshot after every move and restores one on load.

import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefix of every progress-save key. [puzzleSaveKey] builds on it and
/// [parsePuzzleSaveKey] strips it, so the key format lives in this file only.
const puzzleSaveKeyPrefix = 'save.';

/// Key under which a puzzle's progress is stored: one save per image + size.
String puzzleSaveKey({
  required String imageId,
  required int columns,
  required int rows,
}) => '$puzzleSaveKeyPrefix$imageId.${columns}x$rows';

/// Greedy image id, so the grid suffix anchors at the key's LAST dot (ids
/// are dot-free today, but a foreign dot must not shift the grid). Grid
/// digits are capped at 4 so an overflow-length run is rejected the same
/// way on every platform (web ints would parse it instead of overflowing).
final _saveKeyPattern = RegExp(r'^(.+)\.(\d{1,4})x(\d{1,4})$');

/// The image and grid a save key was built for, or null for keys that do
/// not follow the [puzzleSaveKey] format (foreign preference entries).
({String imageId, int columns, int rows})? parsePuzzleSaveKey(String key) {
  if (!key.startsWith(puzzleSaveKeyPrefix)) {
    return null;
  }
  final match = _saveKeyPattern.firstMatch(
    key.substring(puzzleSaveKeyPrefix.length),
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

/// Snapshot of one puzzle in progress.
class PuzzleSaveState {
  const PuzzleSaveState({
    required this.trayPieceIndexes,
    required this.lockedPieceIndexes,
    required this.loosePiecePositions,
    this.startedDay,
    this.boardWidth,
  });

  /// Pieces still in the tray, in display order.
  final List<int> trayPieceIndexes;

  /// Pieces locked into their correct board position.
  final List<int> lockedPieceIndexes;

  /// Loose pieces lying on the board: piece index -> world position.
  final Map<int, Vector2> loosePiecePositions;

  /// Day key ("2026-11-02") of the day this run STARTED, carried unchanged
  /// across re-saves. The daily streak credits a run by this day, so a save
  /// cannot claim a day it was not actually begun on. Null for saves written
  /// before the field existed — those credit nothing.
  final String? startedDay;

  /// Source-image width in pixels when the snapshot was written. World
  /// coordinates ARE image pixels, so a snapshot only restores onto an image
  /// of the same width — against a resized photo its positions and group
  /// offsets are at the wrong scale (pieces pile into one corner, joined
  /// chunks dissolve). Null for saves written before the field existed
  /// (i.e. before the 3072px photo swap) — those start fresh.
  final int? boardWidth;

  /// True when every piece appears exactly once. Guards against loading a
  /// snapshot written for a different grid size, or corrupted data.
  bool isConsistentFor(int totalPieces) {
    final indexes = [
      ...trayPieceIndexes,
      ...lockedPieceIndexes,
      ...loosePiecePositions.keys,
    ];
    final uniqueIndexes = indexes.toSet();
    final hasExpectedCount = indexes.length == totalPieces;
    final hasNoDuplicates = uniqueIndexes.length == indexes.length;
    final hasValidIndexes = indexes.every(
      (index) => index >= 0 && index < totalPieces,
    );

    return hasExpectedCount && hasNoDuplicates && hasValidIndexes;
  }

  String toJsonString() => jsonEncode({
    'tray': trayPieceIndexes,
    'locked': lockedPieceIndexes,
    'loose': {
      for (final entry in loosePiecePositions.entries)
        '${entry.key}': [entry.value.x, entry.value.y],
    },
    if (startedDay != null) 'started': startedDay,
    if (boardWidth != null) 'board': boardWidth,
  });

  /// Returns null when [raw] is not a valid snapshot.
  static PuzzleSaveState? fromJsonString(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // Copying the lists checks every element's type inside this try block.
      return PuzzleSaveState(
        trayPieceIndexes: List<int>.from(data['tray'] as List),
        lockedPieceIndexes: List<int>.from(data['locked'] as List),
        loosePiecePositions: _parseLoosePiecePositions(
          data['loose'] as Map<String, dynamic>,
        ),
        startedDay: data['started'] as String?,
        boardWidth: data['board'] as int?,
      );
    } on Object {
      return null; // Malformed data: treat as "no save".
    }
  }

  /// Converts JSON entries like "3": [50, 70] into piece positions.
  static Map<int, Vector2> _parseLoosePiecePositions(
    Map<String, dynamic> data,
  ) {
    final positions = <int, Vector2>{};
    for (final entry in data.entries) {
      final pieceIndex = int.parse(entry.key);
      final coordinates = entry.value as List;
      final x = (coordinates[0] as num).toDouble();
      final y = (coordinates[1] as num).toDouble();
      positions[pieceIndex] = Vector2(x, y);
    }
    return positions;
  }
}

/// Reads and writes puzzle snapshots by key.
abstract class PuzzleSaveStore {
  Future<PuzzleSaveState?> load(String key);
  Future<void> save(String key, PuzzleSaveState state);
  Future<void> delete(String key);
  Future<bool> exists(String key);

  /// Keys of every stored save, in no particular order.
  Future<List<String>> listSavedKeys();
}

/// Device-local storage. Failures are logged in debug builds and handled
/// without throwing, so a storage problem does not interrupt gameplay.
class SharedPreferencesSaveStore implements PuzzleSaveStore {
  const SharedPreferencesSaveStore();

  @override
  Future<PuzzleSaveState?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) {
        return null;
      }
      final state = PuzzleSaveState.fromJsonString(raw);
      if (state == null) {
        _logFailure('load', key, 'Saved data is malformed.');
      }
      return state;
    } on Object catch (error) {
      _logFailure('load', key, error);
      return null;
    }
  }

  @override
  Future<void> save(String key, PuzzleSaveState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(key, state.toJsonString());
      if (!saved) {
        _logFailure('save', key, 'Storage returned false.');
      }
    } on Object catch (error) {
      _logFailure('save', key, error);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deleted = await prefs.remove(key);
      if (!deleted) {
        _logFailure('delete', key, 'Storage returned false.');
      }
    } on Object catch (error) {
      _logFailure('delete', key, error);
    }
  }

  @override
  Future<bool> exists(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(key);
    } on Object catch (error) {
      _logFailure('check existence', key, error);
      return false;
    }
  }

  @override
  Future<List<String>> listSavedKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs
          .getKeys()
          .where((key) => key.startsWith(puzzleSaveKeyPrefix))
          .toList();
    } on Object catch (error) {
      _logFailure('list', '$puzzleSaveKeyPrefix*', error);
      return const [];
    }
  }

  void _logFailure(String operation, String key, Object error) {
    if (kDebugMode) {
      debugPrint('Puzzle storage: $operation failed for "$key": $error');
    }
  }
}

/// Keeps snapshots in a plain map; used by tests.
class InMemorySaveStore implements PuzzleSaveStore {
  final Map<String, String> _entries = {};

  @override
  Future<PuzzleSaveState?> load(String key) async {
    final raw = _entries[key];
    return raw == null ? null : PuzzleSaveState.fromJsonString(raw);
  }

  @override
  Future<void> save(String key, PuzzleSaveState state) async {
    _entries[key] = state.toJsonString();
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  @override
  Future<bool> exists(String key) async => _entries.containsKey(key);

  @override
  Future<List<String>> listSavedKeys() async =>
      _entries.keys.where((key) => key.startsWith(puzzleSaveKeyPrefix)).toList();
}
