// The bonus track's arithmetic (owner's design, 2026-11-13; hand-placement
// 2026-11-26): every gift board is 25 pieces; pieces come from first
// finishes of gallery paintings (gifts themselves never count — owner
// ruling) plus one piece per 3 consecutive streak days; the journey opens
// at 5 finished paintings; and boards — and their gifts — advance only by
// the player PLACING pieces, never by earning alone.

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/bonus_placement.dart';
import 'package:jigsaw_puzzle/bonus_track.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

BonusTrackState _state(
  int firstFinishes, {
  int streakPieces = 0,
  BonusPlacement placement = BonusPlacement.none,
}) => bonusTrackStateFor(
  firstFinishes: firstFinishes,
  streakPieces: streakPieces,
  placement: placement,
  bonusCatalog: giftFixtures,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('journey gate', () {
    test('stays closed until the fifth finished painting', () {
      expect(_state(0).journeyUnlocked, isFalse);
      expect(_state(0).finishesUntilJourney, 5);
      expect(_state(4).journeyUnlocked, isFalse);
      expect(_state(4).finishesUntilJourney, 1);
      expect(_state(5).journeyUnlocked, isTrue);
      expect(_state(5).finishesUntilJourney, 0);
    });

    test('streak pieces alone do not open the journey', () {
      // The gate counts finished paintings, not pieces (owner's words:
      // "if a user can finish first 5 puzzles, we unlock the journey").
      final state = _state(2, streakPieces: 10);
      expect(state.journeyUnlocked, isFalse);
      expect(state.totalPieces, 12);
    });
  });

  group('bonusTrackStateFor', () {
    test('both sources land as loose pieces on the same 25-piece board', () {
      final state = _state(20, streakPieces: 3);
      expect(state.unlocked, isEmpty);
      expect(state.currentBoard, giftImageOne);
      expect(state.placedCells, isEmpty);
      expect(state.loosePieces, 23);
      expect(state.piecesOnCurrentBoard, 23);
      expect(state.totalPieces, 23);
    });

    test('earning alone never unlocks: 25 earned is 25 loose, no gift', () {
      final state = _state(25);
      expect(state.unlocked, isEmpty);
      expect(state.currentBoard, giftImageOne);
      expect(state.loosePieces, 25);

      // Pieces earned past the board's open slots wait silently.
      expect(_state(26).loosePieces, 25);
    });

    test('placed cells and loose pieces split the earned total', () {
      final state = _state(
        12,
        placement: const BonusPlacement(placedCells: {0, 7, 19}),
      );
      expect(state.placedCells, {0, 7, 19});
      expect(state.loosePieces, 9);
      expect(state.piecesOnCurrentBoard, 12);
    });

    test('a hand-placed board rolls into unlocked and the next starts', () {
      final state = _state(
        26,
        placement: const BonusPlacement(completedBoards: 1),
      );
      expect(state.unlocked, [giftImageOne]);
      expect(state.currentBoard, giftImageTwo);
      expect(state.placedCells, isEmpty);
      expect(state.loosePieces, 1);
    });

    test('placing the last board completes the track; extras are ignored', () {
      final state = _state(
        90,
        placement: const BonusPlacement(completedBoards: 2),
      );
      expect(state.unlocked, giftFixtures);
      expect(state.currentBoard, isNull);
      expect(state.trackComplete, isTrue);
      expect(state.loosePieces, 0);
      expect(state.piecesOnCurrentBoard, 0);
    });

    test('a debug wipe of earnings never shows negative loose pieces', () {
      // Completions cleared while placement survived: placed stays shown
      // (the player did place them), loose floors at zero.
      final state = _state(
        1,
        placement: const BonusPlacement(placedCells: {0, 1, 2, 3, 4}),
      );
      expect(state.placedCells, hasLength(5));
      expect(state.loosePieces, 0);
    });
  });

  group('galleryFirstFinishCount', () {
    test('gift paintings never fund the next gift (owner ruling)', () {
      // Pinned on the REAL catalog too: flipping this rule after launch
      // would retroactively shift every player's derived progress and
      // could re-lock an already-shown gift.
      expect(
        galleryFirstFinishCount({'a', 'b', 'gift-1'}, bonusCatalog: giftFixtures),
        2,
      );
      expect(
        galleryFirstFinishCount({
          'a',
          for (final gift in bonusPuzzleCatalog) gift.id,
        }),
        1,
      );
    });
  });

  group('streakPieces', () {
    test('one piece per 3 consecutive days, per unbroken run', () {
      expect(streakPieces(const <String>{}), 0);
      expect(streakPieces(const {'2026-11-01', '2026-11-02'}), 0);
      expect(streakPieces(const {'2026-11-01', '2026-11-02', '2026-11-03'}), 1);
      // A 7-day run has earned two (days 3 and 6).
      expect(
        streakPieces({
          for (var day = 1; day <= 7; day++)
            '2026-11-${day.toString().padLeft(2, '0')}',
        }),
        2,
      );
    });

    test('a broken streak starts counting over', () {
      // Two 2-day runs never reach 3; two 3-day runs earn one each.
      expect(
        streakPieces(const {
          '2026-11-01', '2026-11-02',
          '2026-11-04', '2026-11-05',
        }),
        0,
      );
      expect(
        streakPieces(const {
          '2026-11-01', '2026-11-02', '2026-11-03',
          '2026-11-05', '2026-11-06', '2026-11-07',
        }),
        2,
      );
    });

    test('runs continue across month ends; bad keys are skipped', () {
      expect(
        streakPieces(const {'2026-11-29', '2026-11-30', '2026-12-01'}),
        1,
      );
      expect(streakPieces(const {'garbage', '2026-11-03'}), 0);
    });
  });

  test('gift unlock order is append-only', () {
    // Unlocks are positional: anyone editing the gift list must re-check
    // this pin knowingly — inserting or reordering shipped entries would
    // re-lock gifts players already earned (owner ruling, 2026-11-13).
    expect([for (final gift in bonusPuzzleCatalog) gift.id], [
      'bonus-evening-hearth',
      'bonus-lakeside-gold',
      'bonus-peony-table',
    ]);
  });

  group('completedImageIds', () {
    test('counts each image once across sizes and skips corrupt records', () async {
      final day = DateTime(2026, 11, 1);
      SharedPreferences.setMockInitialValues({
        puzzleCompletionKey(imageId: 'twice-done', columns: 5, rows: 5):
            completionJson(day),
        puzzleCompletionKey(imageId: 'twice-done', columns: 10, rows: 10):
            completionJson(day),
        puzzleCompletionKey(imageId: 'once-done', columns: 5, rows: 5):
            completionJson(day),
        // Corrupt records read "never completed" on every surface — the
        // track included.
        puzzleCompletionKey(imageId: 'corrupt', columns: 5, rows: 5): '{broken',
        // Foreign keys (saves, settings) are not completions.
        'save.something.5x5': 'ignored',
      });

      final ids = await completedImageIds(
        const SharedPreferencesCompletionStore(),
      );

      expect(ids, {'twice-done', 'once-done'});
    });

    test('counts ids that left the catalog, so progress never regresses', () async {
      SharedPreferences.setMockInitialValues({
        puzzleCompletionKey(imageId: 'retired-photo', columns: 5, rows: 5):
            completionJson(DateTime(2026, 11, 1)),
      });

      final ids = await completedImageIds(
        const SharedPreferencesCompletionStore(),
      );

      expect(ids, {'retired-photo'});
    });
  });
}
