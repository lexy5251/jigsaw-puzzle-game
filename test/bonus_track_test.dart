// The bonus track's arithmetic (owner's design, 2026-11-13): every gift
// board is 25 pieces; pieces come from first finishes of gallery paintings
// (gifts themselves never count — owner ruling) plus one piece per 3
// consecutive streak days; the journey opens at 5 finished paintings; and
// unlocks fire exactly on 25-piece boundaries.

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/bonus_track.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

BonusTrackState _state(int firstFinishes, {int streakPieces = 0}) =>
    bonusTrackStateFor(
      firstFinishes: firstFinishes,
      streakPieces: streakPieces,
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
    test('both sources fill the same 25-piece board', () {
      final state = _state(20, streakPieces: 3);
      expect(state.unlocked, isEmpty);
      expect(state.currentBoard, giftImageOne);
      expect(state.piecesOnCurrentBoard, 23);
      expect(state.totalPieces, 23);
    });

    test('a full board rolls into unlocked and the next board starts', () {
      final state = _state(25);
      expect(state.unlocked, [giftImageOne]);
      expect(state.currentBoard, giftImageTwo);
      expect(state.piecesOnCurrentBoard, 0);

      expect(_state(26).piecesOnCurrentBoard, 1);
    });

    test('the last board completes the track; extra pieces are ignored', () {
      final state = _state(50);
      expect(state.unlocked, giftFixtures);
      expect(state.currentBoard, isNull);
      expect(state.trackComplete, isTrue);
      expect(state.piecesOnCurrentBoard, 0);

      expect(_state(90).trackComplete, isTrue);
    });
  });

  group('newlyUnlockedBonus', () {
    test('fires exactly when a write crosses a 25-piece boundary', () {
      expect(
        newlyUnlockedBonus(piecesBefore: 24, piecesAfter: 25, bonusCatalog: giftFixtures),
        giftImageOne,
      );
      expect(
        newlyUnlockedBonus(piecesBefore: 49, piecesAfter: 50, bonusCatalog: giftFixtures),
        giftImageTwo,
      );
      // A daily finish can add a finish piece AND a streak piece at once.
      expect(
        newlyUnlockedBonus(piecesBefore: 24, piecesAfter: 26, bonusCatalog: giftFixtures),
        giftImageOne,
      );
    });

    test('stays quiet mid-board, on replays, and past the last board', () {
      expect(
        newlyUnlockedBonus(piecesBefore: 10, piecesAfter: 11, bonusCatalog: giftFixtures),
        isNull,
      );
      // A replay adds no distinct id: before and after counts are equal.
      expect(
        newlyUnlockedBonus(piecesBefore: 25, piecesAfter: 25, bonusCatalog: giftFixtures),
        isNull,
      );
      expect(
        newlyUnlockedBonus(piecesBefore: 50, piecesAfter: 51, bonusCatalog: giftFixtures),
        isNull,
      );
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
