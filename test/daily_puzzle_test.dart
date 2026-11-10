import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';

void main() {
  const testCatalog = [
    PuzzleImage(id: 'a', title: 'A', categoryId: 't', fileName: 'a.jpg'),
    PuzzleImage(id: 'b', title: 'B', categoryId: 't', fileName: 'b.jpg'),
    PuzzleImage(id: 'c', title: 'C', categoryId: 't', fileName: 'c.jpg'),
    PuzzleImage(id: 'd', title: 'D', categoryId: 't', fileName: 'd.jpg'),
    PuzzleImage(id: 'e', title: 'E', categoryId: 't', fileName: 'e.jpg'),
  ];

  group('dayKey', () {
    test('zero-pads month and day', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKey(DateTime(2026, 11, 2)), '2026-11-02');
    });

    test('ignores the time of day', () {
      expect(dayKey(DateTime(2026, 11, 2, 23, 59)), '2026-11-02');
    });
  });

  group('utcMidnight', () {
    test('drops the time of day and pins UTC', () {
      final midnight = utcMidnight(DateTime(2026, 11, 2, 23, 59));
      expect(midnight, DateTime.utc(2026, 11, 2));
      expect(midnight.isUtc, isTrue);
    });
  });

  group('dailyPuzzleFor', () {
    test('is pinned to the date, not the time of day', () {
      final morning = dailyPuzzleFor(
        DateTime(2026, 11, 2, 0, 1),
        catalog: testCatalog,
      );
      final night = dailyPuzzleFor(
        DateTime(2026, 11, 2, 23, 59),
        catalog: testCatalog,
      );
      expect(morning.id, night.id);
    });

    test('matches the pinned picks', () {
      // Golden values: changing the seed string or hash would switch every
      // player's daily puzzle mid-day.
      expect(
        dailyPuzzleFor(DateTime(2026, 11, 2), catalog: testCatalog).id,
        'd',
      );
      expect(
        dailyPuzzleFor(DateTime(2026, 11, 3), catalog: testCatalog).id,
        'c',
      );
      expect(
        dailyPuzzleFor(DateTime(2026, 12, 25), catalog: testCatalog).id,
        'a',
      );
    });

    test('varies across days', () {
      final ids = <String>{
        for (var i = 0; i < 30; i++)
          dailyPuzzleFor(DateTime(2026, 11, 1 + i), catalog: testCatalog).id,
      };
      expect(ids.length, greaterThan(1));
    });

    test('uses the real catalog by default', () {
      final pick = dailyPuzzleFor(DateTime(2026, 11, 2));
      expect(puzzleCatalog.map((image) => image.id), contains(pick.id));
    });
  });

  group('dailyCreditDay', () {
    // Pinned picks for testCatalog: 11-01 → 'a', 11-02 → 'd', 11-03 → 'c',
    // 11-04 → 'c' (same image two days running, a real 1-in-catalog case).

    test("credits the day a run of that day's daily began", () {
      expect(
        dailyCreditDay(
          'd',
          DateTime(2026, 11, 2, 15),
          startedDay: '2026-11-02',
          catalog: testCatalog,
        ),
        '2026-11-02',
      );
    });

    test('a run finished the day after it began keeps its own pot', () {
      // Started 11-02 at 23:50 and finished 00:05 on 11-03 — live across
      // midnight, or saved at night and resumed next morning. Same inputs.
      expect(
        dailyCreditDay(
          'd',
          DateTime(2026, 11, 3, 0, 5),
          startedDay: '2026-11-02',
          catalog: testCatalog,
        ),
        '2026-11-02',
      );
    });

    test("a run of yesterday's image STARTED today credits nothing", () {
      // The player skipped 11-02. Opening its image on 11-03 — fresh, or
      // quit-and-reopened the same day — stamps 11-03, which must not
      // repair the missed day.
      expect(
        dailyCreditDay(
          'd',
          DateTime(2026, 11, 3, 9),
          startedDay: '2026-11-03',
          catalog: testCatalog,
        ),
        isNull,
      );
    });

    test("credits nothing for an image that was not its start day's daily", () {
      expect(
        dailyCreditDay(
          'b',
          DateTime(2026, 11, 2, 15),
          startedDay: '2026-11-02',
          catalog: testCatalog,
        ),
        isNull,
      );
    });

    test('credits nothing when finished more than a day late', () {
      expect(
        dailyCreditDay(
          'd',
          DateTime(2026, 11, 4, 15),
          startedDay: '2026-11-02',
          catalog: testCatalog,
        ),
        isNull,
      );
    });

    test('same daily two days running: each run credits its own start day', () {
      // 'c' is the daily for both 11-03 and 11-04 — the stamp resolves the
      // ambiguity the old resumed-flag heuristic could not.
      expect(
        dailyCreditDay(
          'c',
          DateTime(2026, 11, 4, 9),
          startedDay: '2026-11-03',
          catalog: testCatalog,
        ),
        '2026-11-03',
      );
      expect(
        dailyCreditDay(
          'c',
          DateTime(2026, 11, 4, 9),
          startedDay: '2026-11-04',
          catalog: testCatalog,
        ),
        '2026-11-04',
      );
    });

    test('a save without a stamp (pre-upgrade) credits nothing', () {
      expect(
        dailyCreditDay(
          'd',
          DateTime(2026, 11, 2, 15),
          startedDay: null,
          catalog: testCatalog,
        ),
        isNull,
      );
    });

    test('a malformed or normalizable stamp credits nothing', () {
      // DateTime.tryParse would roll '2026-11-31' over to December 1; the
      // round-trip check must reject it rather than credit a ghost day.
      for (final bad in ['garbage', '2026-11-31', '20261102']) {
        expect(
          dailyCreditDay(
            'd',
            DateTime(2026, 11, 2, 15),
            startedDay: bad,
            catalog: testCatalog,
          ),
          isNull,
          reason: 'startedDay "$bad" must not credit',
        );
      }
    });

    test('a clock that ran backwards credits nothing', () {
      expect(
        dailyCreditDay(
          'd',
          DateTime(2026, 11, 1, 23),
          startedDay: '2026-11-02',
          catalog: testCatalog,
        ),
        isNull,
      );
    });
  });

  group('currentStreak', () {
    final today = DateTime(2026, 11, 2, 15, 30);

    test('is zero with no completed days', () {
      expect(currentStreak({}, today), 0);
    });

    test('counts a run ending today', () {
      final days = {'2026-11-02', '2026-11-01', '2026-10-31'};
      expect(currentStreak(days, today), 3);
    });

    test('stays alive while today is not played yet', () {
      final days = {'2026-11-01', '2026-10-31'};
      expect(currentStreak(days, today), 2);
    });

    test('breaks after a fully missed day', () {
      final days = {'2026-10-31', '2026-10-30'};
      expect(currentStreak(days, today), 0);
    });

    test('ignores runs on the far side of a gap', () {
      final days = {'2026-11-02', '2026-10-30', '2026-10-29'};
      expect(currentStreak(days, today), 1);
    });

    test('crosses month and year boundaries', () {
      final days = {'2026-01-01', '2025-12-31'};
      expect(currentStreak(days, DateTime(2026, 1, 1)), 2);
    });
  });

  group('longestStreak', () {
    test('is zero with no completed days', () {
      expect(longestStreak({}), 0);
    });

    test('counts a single day', () {
      expect(longestStreak({'2026-11-02'}), 1);
    });

    test('finds the longest run among several', () {
      final days = {
        '2026-10-01', '2026-10-02', '2026-10-03', // three in a row
        '2026-10-20', '2026-10-21', // two in a row
        '2026-11-02', // alone
      };
      expect(longestStreak(days), 3);
    });

    test('ignores malformed stored keys', () {
      expect(longestStreak({'garbage', '2026-11-02'}), 1);
    });

    test('counts calendar days across daylight-saving changes', () {
      expect(longestStreak({'2026-03-07', '2026-03-08', '2026-03-09'}), 3);
      expect(longestStreak({'2026-10-31', '2026-11-01', '2026-11-02'}), 3);
    });
  });

}
