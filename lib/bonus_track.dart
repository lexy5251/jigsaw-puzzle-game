// Bonus track overview (owner's design, 2026-11-13; hand-placement
// 2026-11-26):
// 1. The journey OPENS after the player finishes their first 5 paintings;
//    before that, the Collection tab shows a teaser.
// 2. Every gift board is a 25-piece puzzle (one size, always). One piece is
//    earned per FIRST finish of each gallery painting (replays and the gift
//    puzzles themselves earn nothing — owner rulings), plus one piece for
//    every 3 consecutive days of the daily streak.
// 3. EARNING is DERIVED from the permanent completion records and the
//    streak day set — no counter to keep consistent: a failed completion
//    write simply earns its piece when the retry lands.
// 4. PLACING is the player's job (owner ruling, 2026-11-26): earned pieces
//    wait loose on the Collection board until dragged into place, and a
//    board — and its gift — completes only when its last piece is placed
//    there. What has been placed lives in bonus_placement.dart.

import 'dart:math' as math;

import 'bonus_placement.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';

/// Finished paintings needed before the journey appears in Collection.
const journeyUnlockFinishes = 5;

/// Every gift board's size — one size for every gift (owner ruling: a
/// varying size would confuse players).
const bonusBoardPieces = 25;

/// Every this many consecutive streak days earns one extra piece.
const streakDaysPerPiece = 3;

/// Where the player stands on the track, derived by [bonusTrackStateFor].
class BonusTrackState {
  const BonusTrackState({
    required this.firstFinishes,
    required this.totalPieces,
    required this.unlocked,
    required this.currentBoard,
    required this.placedCells,
    required this.loosePieces,
    required this.earningComplete,
  });

  /// Distinct gallery paintings finished at least once.
  final int firstFinishes;

  /// Earned pieces ever: [firstFinishes] plus the streak pieces.
  final int totalPieces;

  /// Gift paintings whose boards were fully placed, in unlock order.
  final List<PuzzleImage> unlocked;

  /// The board assembling now; null once every gift is placed.
  final PuzzleImage? currentBoard;

  /// Cells of [currentBoard] the player has snapped in (row-major 0..24).
  final Set<int> placedCells;

  /// Earned pieces waiting loose on [currentBoard], capped at its open
  /// slots — pieces earned beyond that wait silently for the next board.
  final int loosePieces;

  /// What the current board holds, placed and waiting alike — the count a
  /// just-opened journey promises as the head start.
  int get piecesOnCurrentBoard => placedCells.length + loosePieces;

  /// Whether every board's worth of pieces has been EARNED — nothing more
  /// can ever be banked, however much of it still waits to be placed. The
  /// daily card's "to a bonus piece" hook retires on this, not on
  /// [trackComplete]: earning capacity is what the hook promises.
  final bool earningComplete;

  /// The Collection tab shows a teaser until this flips.
  bool get journeyUnlocked => firstFinishes >= journeyUnlockFinishes;

  /// Finishes still needed before the journey opens.
  int get finishesUntilJourney =>
      journeyUnlocked ? 0 : journeyUnlockFinishes - firstFinishes;

  bool get trackComplete => currentBoard == null;
}

/// Folds the two earning sources and the player's hand-placed progress
/// into one board state. Boards advance only by PLACEMENT; pieces earned
/// beyond the last board are ignored — finishing more paintings after the
/// track is done stays a plain pleasure, not an overflow.
BonusTrackState bonusTrackStateFor({
  required int firstFinishes,
  required int streakPieces,
  BonusPlacement placement = BonusPlacement.none,
  List<PuzzleImage> bonusCatalog = bonusPuzzleCatalog,
}) {
  final totalPieces = firstFinishes + streakPieces;
  final boards = math.min(placement.completedBoards, bonusCatalog.length);
  final complete = boards == bonusCatalog.length;
  final placedCells = complete ? const <int>{} : placement.placedCells;
  // Loose pieces are earned-but-unplaced, floored at zero so a debug wipe
  // of the completion records can never show negative pieces.
  final loose = complete
      ? 0
      : math.max(
          0,
          math.min(
            totalPieces - (boards * bonusBoardPieces + placedCells.length),
            bonusBoardPieces - placedCells.length,
          ),
        );
  return BonusTrackState(
    firstFinishes: firstFinishes,
    totalPieces: totalPieces,
    unlocked: bonusCatalog.sublist(0, boards),
    currentBoard: complete ? null : bonusCatalog[boards],
    placedCells: placedCells,
    loosePieces: loose,
    earningComplete:
        totalPieces >= bonusCatalog.length * bonusBoardPieces,
  );
}

/// Distinct image ids in an already-loaded completion snapshot (see
/// [PuzzleCompletionQuery.loadAllCompletionRecords], whose validity rule —
/// corrupt reads as "never completed" — the snapshot already applied).
/// Ids are counted whether or not they are still in the catalog, so track
/// progress never regresses when paintings are renamed out of it.
Set<String> imageIdsFromCompletions(Map<String, CompletionRecord> completions) {
  final ids = <String>{};
  for (final key in completions.keys) {
    final parsed = parsePuzzleCompletionKey(key);
    if (parsed != null) {
      ids.add(parsed.imageId);
    }
  }
  return ids;
}

/// [imageIdsFromCompletions] straight off the store, for callers without a
/// snapshot of their own (the completion flow reads once per finish).
Future<Set<String>> completedImageIds(PuzzleCompletionStore store) async =>
    imageIdsFromCompletions(await store.loadAllCompletionRecords());

/// First-finish count toward the track: gift paintings are pure rewards
/// and never fund the next gift (owner ruling, 2026-11-13) — pinned by
/// test so the rule cannot silently flip and retroactively shift every
/// player's derived progress.
int galleryFirstFinishCount(
  Set<String> completedIds, {
  List<PuzzleImage> bonusCatalog = bonusPuzzleCatalog,
}) {
  final giftIds = {for (final gift in bonusCatalog) gift.id};
  return completedIds.where((id) => !giftIds.contains(id)).length;
}

/// Extra pieces from the daily streak: one per [streakDaysPerPiece]
/// consecutive completed days, summed over every unbroken run in the
/// player's history (a 7-day run has earned 2). Derived from the streak
/// store's day set, so it needs no storage of its own.
int streakPieces(Iterable<String> completedDays) {
  // Day keys are "YYYY-MM-DD"; malformed ones are skipped. Days are
  // compared as plain UTC dates — DateTime.parse would give local
  // midnights whose differences wobble across daylight-saving changes.
  final dates = <DateTime>[];
  for (final day in completedDays) {
    final parts = day.split('-');
    if (parts.length != 3) {
      continue;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final dayOfMonth = int.tryParse(parts[2]);
    if (year == null || month == null || dayOfMonth == null) {
      continue;
    }
    dates.add(DateTime.utc(year, month, dayOfMonth));
  }
  dates.sort();

  var pieces = 0;
  var runLength = 0;
  DateTime? previous;
  for (final date in dates) {
    if (previous != null && date.difference(previous).inDays == 1) {
      runLength++;
    } else {
      pieces += runLength ~/ streakDaysPerPiece;
      runLength = 1;
    }
    previous = date;
  }
  pieces += runLength ~/ streakDaysPerPiece;
  return pieces;
}
