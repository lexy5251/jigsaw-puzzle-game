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

/// Key under which a puzzle's progress is stored: one save per image + size.
String puzzleSaveKey({
  required String imageId,
  required int columns,
  required int rows,
}) => 'save.$imageId.${columns}x$rows';

/// Snapshot of one puzzle in progress.
class PuzzleSaveState {
  const PuzzleSaveState({
    required this.trayPieceIndexes,
    required this.lockedPieceIndexes,
    required this.loosePiecePositions,
  });

  /// Pieces still in the tray, in display order.
  final List<int> trayPieceIndexes;

  /// Pieces locked into their correct board position.
  final List<int> lockedPieceIndexes;

  /// Loose pieces lying on the board: piece index -> world position.
  final Map<int, Vector2> loosePiecePositions;

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
}
