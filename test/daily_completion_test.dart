import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Covers the game screen marking the daily streak on completion.
void main() {
  // A fixed clock pins which catalog image is "today's daily"; the test
  // images borrow that ID but render the small test photo.
  DateTime fixedNow() => DateTime(2026, 11, 6, 14);
  final dailyImage = PuzzleImage(
    id: dailyPuzzleFor(fixedNow()).id,
    title: 'Daily test puzzle',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  );
  const otherImage = PuzzleImage(
    id: 'not-the-daily',
    title: 'Other test puzzle',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  );
  const dailyDaysKey = 'flutter.daily.days';
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
  });

  Future<JigsawGame> boot(
    WidgetTester tester,
    PuzzleImage image, {
    DateTime Function()? clock,
    String? savedStartedDay,
  }) {
    // Seed a save with the single piece loose on the board, so completing
    // the puzzle is one settle() call instead of a tray drag. The stamp
    // says which day the run began — the day a finish credits.
    prefs.storage['flutter.save.${image.id}.1x1'] = singleLoosePieceSave(
      startedDay: savedStartedDay ?? dayKey((clock ?? fixedNow)()),
    ).toJsonString();

    return bootGameScreen(
      tester,
      image: image,
      size: singlePieceSize,
      clock: clock ?? fixedNow,
    );
  }

  testWidgets("finishing today's daily image marks the day", (tester) async {
    final game = await boot(tester, dailyImage);
    await completePuzzle(tester, game);

    expect(prefs.storage[dailyDaysKey], contains('2026-11-06'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("finishing yesterday's daily past midnight blooms its pot", (
    tester,
  ) async {
    // The 2026-11-06 daily was saved that night and finished at 00:05 on
    // 11-07; the save's start-day stamp still blooms 11-06's pot.
    DateTime justPastMidnight() => DateTime(2026, 11, 7, 0, 5);
    // Guard: the grace path is only exercised when the pick really changed.
    expect(dailyPuzzleFor(justPastMidnight()).id, isNot(dailyImage.id));

    final game = await boot(
      tester,
      dailyImage,
      clock: justPastMidnight,
      savedStartedDay: '2026-11-06',
    );
    await completePuzzle(tester, game);

    expect(prefs.storage[dailyDaysKey], contains('2026-11-06'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stale save of the daily image credits nothing', (
    tester,
  ) async {
    // An abandoned run from an earlier rotation of the same image: its
    // stamp is weeks old, so finishing it must not bloom any pot.
    final game = await boot(tester, dailyImage, savedStartedDay: '2026-10-01');
    await completePuzzle(tester, game);

    expect(prefs.storage.containsKey(dailyDaysKey), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('finishing any other image leaves the streak alone', (
    tester,
  ) async {
    final game = await boot(tester, otherImage);
    await completePuzzle(tester, game);

    expect(prefs.storage.containsKey(dailyDaysKey), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed streak write keeps the progress save for a retry', (
    tester,
  ) async {
    prefs.onWrite = (key) => key != dailyDaysKey;
    final game = await boot(tester, dailyImage);
    await completePuzzle(tester, game);

    // The completion record landed but the day did not; the save must
    // survive so resuming and finishing again retries the credit.
    expect(prefs.storage[dailyDaysKey], isNull);
    expect(
      prefs.storage.keys.where((key) => key.startsWith('flutter.done.')),
      isNotEmpty,
    );
    expect(
      prefs.storage.containsKey('flutter.save.${dailyImage.id}.1x1'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('re-finishing the kept save retries the daily credit', (
    tester,
  ) async {
    prefs.onWrite = (key) => key != dailyDaysKey;
    final game = await boot(tester, dailyImage);
    await completePuzzle(tester, game);
    await tester.pumpWidget(const SizedBox.shrink());

    // Storage recovers; the player resumes the kept save (an app restart
    // in between) and finishes again.
    prefs.onWrite = null;
    SharedPreferences.resetStatic();
    final resumed = await bootGameScreen(
      tester,
      image: dailyImage,
      size: singlePieceSize,
      clock: fixedNow,
    );
    await completePuzzle(tester, resumed);

    expect(prefs.storage[dailyDaysKey], contains('2026-11-06'));
    expect(
      prefs.storage.containsKey('flutter.save.${dailyImage.id}.1x1'),
      isFalse,
    );
    // The completion record counts both finishes — the accepted cost of
    // reusing the progress save as the retry vehicle.
    final record = await const SharedPreferencesCompletionStore().record(
      puzzleCompletionKey(imageId: dailyImage.id, columns: 1, rows: 1),
    );
    expect(record!.count, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the streak survives a failed completion-record write', (
    tester,
  ) async {
    prefs.onWrite = (key) => !key.startsWith('flutter.done.');
    final game = await boot(tester, dailyImage);
    await completePuzzle(tester, game);

    // The player saw the puzzle finish: the day is credited even though the
    // completion record (and so the progress save) is retried later.
    expect(prefs.storage[dailyDaysKey], contains('2026-11-06'));
    expect(
      prefs.storage.keys.where((key) => key.startsWith('flutter.done.')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
