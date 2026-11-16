import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/my_puzzles.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

/// Pure My Puzzles aggregation: which stored entries become list rows, and
/// in what order.
void main() {
  const imageA = PuzzleImage(
    id: 'a',
    title: 'A',
    categoryId: 'test',
    fileName: 'a.webp',
  );
  const imageB = PuzzleImage(
    id: 'b',
    title: 'B',
    categoryId: 'test',
    fileName: 'b.webp',
  );
  const imageC = PuzzleImage(
    id: 'c',
    title: 'C',
    categoryId: 'test',
    fileName: 'c.webp',
  );
  const catalog = [imageA, imageB, imageC];
  const small = PuzzleSize(columns: 2, rows: 1); // 2 pieces
  const large = PuzzleSize(columns: 2, rows: 2); // 4 pieces
  const sizes = [small, large];

  PuzzleSaveState saveFor(
    PuzzleSize size, {
    String? startedDay,
    int? boardWidth,
    DateTime? savedAt,
  }) => fullTraySave(
    size.pieceCount,
    startedDay: startedDay,
    boardWidth: boardWidth,
    savedAt: savedAt,
  );

  String doneKeyFor(PuzzleImage image, PuzzleSize size) => puzzleCompletionKey(
    imageId: image.id,
    columns: size.columns,
    rows: size.rows,
  );

  MyPuzzlesSummary build({
    Map<String, PuzzleSaveState> saves = const {},
    Map<String, CompletionRecord> completions = const {},
  }) => buildMyPuzzlesSummary(
    saves: saves,
    completions: completions,
    catalog: catalog,
    sizes: sizes,
  );

  test('nothing stored, nothing listed', () {
    final summary = build();
    expect(summary.inProgress, isEmpty);
    expect(summary.finished, isEmpty);
  });

  test('photos sort by their newest run, day-less last, one per photo', () {
    final summary = build(
      saves: {
        seedSaveKey(imageC, small): saveFor(small), // save pre-dates the field
        seedSaveKey(imageA, small): saveFor(small, startedDay: '2026-11-08'),
        seedSaveKey(imageB, small): saveFor(small), // older than b's 2x2 run
        seedSaveKey(imageB, large): saveFor(large, startedDay: '2026-11-10'),
      },
    );

    // b's newest (2x2) run stands for the photo; its day-less run folds in.
    expect(
      [
        for (final run in summary.inProgress)
          (run.image.id, run.size.pieceCount),
      ],
      [('b', 4), ('a', 2), ('c', 2)],
    );
  });

  test('the savedAt stamp outranks the started day, stamp-less last', () {
    final summary = build(
      saves: {
        // Started earliest but touched most recently — must lead.
        seedSaveKey(imageC, small): saveFor(
          small,
          startedDay: '2026-11-01',
          savedAt: DateTime(2026, 11, 12, 21),
        ),
        seedSaveKey(imageA, small): saveFor(
          small,
          startedDay: '2026-11-10',
          savedAt: DateTime(2026, 11, 12, 9),
        ),
        // Pre-stamp save: a newer started day must not beat stamped runs.
        seedSaveKey(imageB, small): saveFor(small, startedDay: '2026-11-11'),
      },
    );

    expect(
      [for (final run in summary.inProgress) run.image.id],
      ['c', 'a', 'b'],
    );
    expect(summary.inProgress.first.savedAt, DateTime(2026, 11, 12, 21));
  });

  test('two stamped runs of one photo keep the newest stamp', () {
    final summary = build(
      saves: {
        seedSaveKey(imageA, small): saveFor(
          small,
          savedAt: DateTime(2026, 11, 12, 9),
        ),
        seedSaveKey(imageA, large): saveFor(
          large,
          savedAt: DateTime(2026, 11, 12, 21),
        ),
      },
    );

    // The newest run stands for the photo on the page AND for the home
    // continue card — it must be the 21:00 one.
    expect(summary.inProgress.single.size, large);
  });

  test('finished photos group their sizes and take the newest date', () {
    final summary = build(
      completions: {
        // Deliberately largest-grid first: the photo's size list must come
        // out in the offered-sizes order, not insertion order.
        doneKeyFor(imageB, large): completionOn(
          DateTime(2026, 11, 9),
          count: 2,
        ),
        doneKeyFor(imageB, small): completionOn(DateTime(2026, 11, 1)),
        doneKeyFor(imageA, small): completionOn(DateTime(2026, 11, 5)),
      },
    );

    expect([for (final photo in summary.finished) photo.image.id], ['b', 'a']);
    final photoB = summary.finished.first;
    expect(photoB.completedSizes, [small, large]);
    expect(photoB.lastCompletedAt, DateTime(2026, 11, 9));
  });

  test('finished photos with equal dates keep catalog order', () {
    final day = DateTime(2026, 11, 9);
    final summary = build(
      completions: {
        doneKeyFor(imageC, small): completionOn(day),
        doneKeyFor(imageA, small): completionOn(day),
      },
    );

    expect([for (final photo in summary.finished) photo.image.id], ['a', 'c']);
  });

  test('entries the page could not open are skipped', () {
    const unknownGrid = PuzzleSize(columns: 9, rows: 9);
    final summary = build(
      saves: {
        'save.gone.2x1': saveFor(small), // photo left the catalog
        seedSaveKey(imageA, unknownGrid): saveFor(unknownGrid),
        'not-a-save-key': saveFor(small),
        // One of two pieces: fails the same consistency check as the badges.
        seedSaveKey(imageB, small): const PuzzleSaveState(
          trayPieceIndexes: [0],
          lockedPieceIndexes: [],
          loosePiecePositions: {},
        ),
      },
      completions: {
        'done.gone.2x1': completionOn(DateTime(2026, 11, 9)),
        doneKeyFor(imageA, unknownGrid): completionOn(DateTime(2026, 11, 9)),
      },
    );

    expect(summary.inProgress, isEmpty);
    expect(summary.finished, isEmpty);
  });

  test('placed count comes from the locked pieces', () {
    final summary = build(
      saves: {
        seedSaveKey(imageA, large): partiallyPlacedSave(
          large.pieceCount,
          placed: 3,
          startedDay: '2026-11-10',
        ),
      },
    );

    expect(summary.inProgress.single.placedCount, 3);
  });

  test('a save written against a different photo width stays listed', () {
    // The game's own scale guard starts it fresh on open; hiding it here
    // would make a visibly started puzzle disappear from the page.
    final summary = build(
      saves: {seedSaveKey(imageA, small): saveFor(small, boardWidth: 9999)},
    );

    expect(summary.inProgress.single.image.id, 'a');
  });

  test('a fully locked save with its record belongs to Finished only', () {
    // An interrupted final snap can leave this pair behind.
    final summary = build(
      saves: {
        seedSaveKey(imageA, small): partiallyPlacedSave(
          small.pieceCount,
          placed: small.pieceCount,
          startedDay: '2026-11-10',
        ),
      },
      completions: {
        doneKeyFor(imageA, small): completionOn(DateTime(2026, 11, 10)),
      },
    );

    expect(summary.inProgress, isEmpty);
    expect(summary.finished.single.image.id, 'a');
  });

  test('a fully locked save WITHOUT its record stays listed', () {
    // No completion record yet: the save is the retry vehicle — opening
    // the puzzle finishes the recording, so it must stay findable.
    final summary = build(
      saves: {
        seedSaveKey(imageA, small): partiallyPlacedSave(
          small.pieceCount,
          placed: small.pieceCount,
        ),
      },
    );

    expect(summary.inProgress.single.image.id, 'a');
  });

  test('a photo finished at one size and mid-way at another shows twice', () {
    final summary = build(
      saves: {
        seedSaveKey(imageA, large): saveFor(large, startedDay: '2026-11-10'),
      },
      completions: {
        doneKeyFor(imageA, small): completionOn(DateTime(2026, 11, 9)),
      },
    );

    expect(summary.inProgress.single.size, large);
    expect(summary.finished.single.completedSizes, [small]);
  });

  test('loadMyPuzzlesSummary reads both stores', () async {
    final saveStore = InMemorySaveStore();
    await saveStore.save(
      seedSaveKey(imageA, small),
      saveFor(small, startedDay: '2026-11-10'),
    );
    final completionStore = InMemoryCompletionStore();
    await completionStore.markCompleted(
      doneKeyFor(imageB, small),
      completedAt: DateTime(2026, 11, 9),
    );

    final summary = await loadMyPuzzlesSummary(
      saveStore: saveStore,
      completionStore: completionStore,
      catalog: catalog,
      sizes: sizes,
    );

    expect(summary.inProgress.single.image.id, 'a');
    expect(summary.finished.single.image.id, 'b');
  });

  test('a pre-loaded saves map replaces the store scan', () async {
    // The home screen scans the save store once per refresh and hands the
    // snapshot in; the summary must then not touch the store at all.
    final summary = await loadMyPuzzlesSummary(
      saveStore: _ThrowingSaveStore(),
      completionStore: InMemoryCompletionStore(),
      saves: {seedSaveKey(imageA, small): saveFor(small)},
      catalog: catalog,
      sizes: sizes,
    );

    expect(summary.inProgress.single.image.id, 'a');
  });

  test('InProgressRun equality covers every field', () {
    InProgressRun run({int placed = 0, DateTime? savedAt}) => InProgressRun(
      image: imageA,
      size: small,
      placedCount: placed,
      savedAt: savedAt,
    );
    final stamp = DateTime(2026, 11, 12, 21);
    expect(run(savedAt: stamp), run(savedAt: stamp));
    expect(run(savedAt: stamp).hashCode, run(savedAt: stamp).hashCode);
    // The home screen's rebuild-skip relies on any rendered change
    // breaking equality.
    expect(run(savedAt: stamp), isNot(run(savedAt: DateTime(2026, 11, 13))));
    expect(run(savedAt: stamp), isNot(run(placed: 1, savedAt: stamp)));
  });
}

/// Fails on any access — proves a code path never reached the store.
class _ThrowingSaveStore implements PuzzleSaveStore {
  @override
  Future<PuzzleSaveState?> load(String key) => throw StateError('load');
  @override
  Future<void> save(String key, PuzzleSaveState state) =>
      throw StateError('save');
  @override
  Future<void> delete(String key) => throw StateError('delete');
  @override
  Future<bool> exists(String key) => throw StateError('exists');
  @override
  Future<List<String>> listSavedKeys() => throw StateError('list');
}
