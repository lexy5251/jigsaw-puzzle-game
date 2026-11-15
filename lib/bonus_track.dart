// Bonus track overview (owner's design, 2026-11-13):
// 1. The journey OPENS after the player finishes their first 5 paintings;
//    before that, the Collection tab shows a teaser.
// 2. Every gift board is a 25-piece puzzle (one size, always). One piece is
//    earned per FIRST finish of each gallery painting (replays and the gift
//    puzzles themselves earn nothing — owner rulings), plus one piece for
//    every 3 consecutive days of the daily streak.
// 3. Progress is DERIVED from the permanent completion records and the
//    streak day set — there is no second counter to keep consistent: a
//    failed completion write simply earns its piece when the retry lands.
// 4. The unlock moment compares the derived piece total before and after
//    one completion's writes; crossing a 25-piece boundary triggers the
//    "Bonus puzzle unlocked" card. Historic progress (records that existed
//    before this feature) unlocks silently in Collection instead.

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
    required this.piecesOnCurrentBoard,
  });

  /// Distinct gallery paintings finished at least once.
  final int firstFinishes;

  /// [firstFinishes] plus the streak pieces.
  final int totalPieces;

  /// Fully earned gift paintings, in unlock order.
  final List<PuzzleImage> unlocked;

  /// The board assembling now; null once every gift is earned.
  final PuzzleImage? currentBoard;

  /// Always below [bonusBoardPieces]: a full board rolls into [unlocked]
  /// and the next one starts. Zero when the track is complete.
  final int piecesOnCurrentBoard;

  /// The Collection tab shows a teaser until this flips.
  bool get journeyUnlocked => firstFinishes >= journeyUnlockFinishes;

  /// Finishes still needed before the journey opens.
  int get finishesUntilJourney =>
      journeyUnlocked ? 0 : journeyUnlockFinishes - firstFinishes;

  bool get trackComplete => currentBoard == null;
}

/// How many boards a piece total has filled, capped at the catalog.
int _boardsCompleted(int totalPieces, int boardCount) {
  final boards = totalPieces ~/ bonusBoardPieces;
  return boards > boardCount ? boardCount : boards;
}

/// Folds the two earning sources into board progress. Pieces beyond the
/// last board are ignored — finishing more paintings after the track is
/// done stays a plain pleasure, not an overflow.
BonusTrackState bonusTrackStateFor({
  required int firstFinishes,
  required int streakPieces,
  List<PuzzleImage> bonusCatalog = bonusPuzzleCatalog,
}) {
  final totalPieces = firstFinishes + streakPieces;
  final boards = _boardsCompleted(totalPieces, bonusCatalog.length);
  final complete = boards == bonusCatalog.length;
  return BonusTrackState(
    firstFinishes: firstFinishes,
    totalPieces: totalPieces,
    unlocked: bonusCatalog.sublist(0, boards),
    currentBoard: complete ? null : bonusCatalog[boards],
    piecesOnCurrentBoard: complete ? 0 : totalPieces - boards * bonusBoardPieces,
  );
}

/// The gift painting a completion just finished the board for, or null when
/// no 25-piece boundary was crossed (replays, mid-board pieces, exhausted
/// track). Callers pass the derived piece totals before and after the
/// writes they are reporting on.
PuzzleImage? newlyUnlockedBonus({
  required int piecesBefore,
  required int piecesAfter,
  List<PuzzleImage> bonusCatalog = bonusPuzzleCatalog,
}) {
  final before = _boardsCompleted(piecesBefore, bonusCatalog.length);
  final after = _boardsCompleted(piecesAfter, bonusCatalog.length);
  return after > before ? bonusCatalog[after - 1] : null;
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
