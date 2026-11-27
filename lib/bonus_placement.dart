// Bonus placement storage overview:
// 1. Earning stays derived (completions + streak, see bonus_track.dart);
//    this file persists only what the player has DONE with earned pieces:
//    how many gift boards they have fully placed by hand, and which cells
//    of the current board are snapped in.
// 2. One shared_preferences entry holds the whole record as JSON — the
//    board is 25 cells, so it stays a few dozen bytes.
// 3. Storage failures never interrupt play: loads fall back to "nothing
//    placed yet", a failed save is logged in debug builds and the next
//    snap retries the whole record (saves are whole-state overwrites).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bonus_track.dart';

/// What the player has placed by hand on the bonus track.
@immutable
class BonusPlacement {
  const BonusPlacement({this.completedBoards = 0, this.placedCells = const {}});

  /// Nothing placed yet — also the fallback for unreadable storage.
  static const none = BonusPlacement();

  /// Gift boards fully placed, in catalog order.
  final int completedBoards;

  /// Cells of the CURRENT board snapped in (row-major 0..24).
  final Set<int> placedCells;

  /// Every piece ever placed, across finished boards and the current one.
  int get placedTotal =>
      completedBoards * bonusBoardPieces + placedCells.length;
}

/// Reads and records the player's hand-placed bonus progress.
abstract class BonusPlacementStore {
  Future<BonusPlacement> load();

  /// Overwrites the whole record. Returns true only when storage holds the
  /// new value afterwards.
  Future<bool> save(BonusPlacement placement);
}

/// Device-local storage. The board is decoration around derived progress,
/// so failures degrade to "place it again" — never to a crash.
class SharedPreferencesBonusPlacementStore implements BonusPlacementStore {
  const SharedPreferencesBonusPlacementStore();

  static const _key = 'bonus.placed';

  @override
  Future<BonusPlacement> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_key));
    } on Object catch (error) {
      _logFailure('read', error);
      return BonusPlacement.none;
    }
  }

  @override
  Future<bool> save(BonusPlacement placement) async {
    SharedPreferences? prefs;
    String? previous;
    var wroteCache = false;
    try {
      prefs = await SharedPreferences.getInstance();
      previous = prefs.getString(_key);
      wroteCache = true;
      final saved = await prefs.setString(_key, _encode(placement));
      if (saved) {
        return true;
      }
      _logFailure('write', 'Storage returned false.');
    } on Object catch (error) {
      _logFailure('write', error);
    }
    // A failed setString still updates the in-memory cache; put the old
    // value back so a later load never shows a placement that was not
    // persisted.
    if (wroteCache) {
      try {
        if (previous == null) {
          await prefs?.remove(_key);
        } else {
          await prefs?.setString(_key, previous);
        }
      } on Object catch (error) {
        _logFailure('cache repair', error);
      }
    }
    return false;
  }

  static String _encode(BonusPlacement placement) => jsonEncode({
    'boards': placement.completedBoards,
    'cells': placement.placedCells.toList()..sort(),
  });

  /// Anything malformed reads as [BonusPlacement.none] — the player simply
  /// places their earned pieces again.
  static BonusPlacement _decode(String? stored) {
    if (stored == null) {
      return BonusPlacement.none;
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) {
        return BonusPlacement.none;
      }
      final boards = decoded['boards'];
      final cells = decoded['cells'];
      if (boards is! int || boards < 0 || cells is! List) {
        return BonusPlacement.none;
      }
      return BonusPlacement(
        completedBoards: boards,
        placedCells: {
          for (final cell in cells)
            if (cell is int && cell >= 0 && cell < bonusBoardPieces) cell,
        },
      );
    } on FormatException {
      return BonusPlacement.none;
    }
  }

  static void _logFailure(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('Bonus placement $operation failed: $error');
    }
  }
}
