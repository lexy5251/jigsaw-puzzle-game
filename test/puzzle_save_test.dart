import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

/// Pure save-model tests: serialization, validation, and the store contract.
void main() {
  test('a snapshot round-trips through JSON', () {
    final state = PuzzleSaveState(
      trayPieceIndexes: const [3, 1, 2],
      lockedPieceIndexes: const [0],
      loosePiecePositions: {4: Vector2(12.5, -7.0), 5: Vector2(0, 300)},
      startedDay: '2026-11-06',
      boardWidth: 3072,
    );

    final restored = PuzzleSaveState.fromJsonString(state.toJsonString())!;

    expect(restored.trayPieceIndexes, [3, 1, 2]);
    expect(restored.lockedPieceIndexes, [0]);
    expect(restored.loosePiecePositions[4], Vector2(12.5, -7.0));
    expect(restored.loosePiecePositions[5], Vector2(0, 300));
    expect(restored.startedDay, '2026-11-06');
    expect(restored.boardWidth, 3072);
  });

  test('a save from before the start-day stamp still loads', () {
    // Players upgrading mid-puzzle have saves without the fields.
    const legacy = '{"tray":[1,0],"locked":[],"loose":{}}';

    final restored = PuzzleSaveState.fromJsonString(legacy)!;

    expect(restored.trayPieceIndexes, [1, 0]);
    expect(restored.startedDay, isNull);
    expect(restored.boardWidth, isNull);
  });

  test('malformed data reads as "no save"', () {
    expect(PuzzleSaveState.fromJsonString('not json at all'), isNull);
    expect(PuzzleSaveState.fromJsonString('{"tray": 3}'), isNull);
    expect(PuzzleSaveState.fromJsonString('{}'), isNull);
  });

  test('invalid piece types are rejected during parsing', () {
    const malformedSnapshots = [
      '{"tray":["0"],"locked":[],"loose":{}}',
      '{"tray":[],"locked":[null],"loose":{}}',
      '{"tray":[],"locked":[],"loose":{"bad-index":[10,20]}}',
      '{"tray":[],"locked":[],"loose":{"0":[10]}}',
      '{"tray":[],"locked":[],"loose":{"0":[10,"bad-y"]}}',
    ];

    for (final raw in malformedSnapshots) {
      expect(PuzzleSaveState.fromJsonString(raw), isNull, reason: raw);
    }
  });

  test('isConsistentFor rejects wrong counts, duplicates, and bad indexes', () {
    PuzzleSaveState state({
      List<int> tray = const [],
      List<int> locked = const [],
      Map<int, Vector2> loose = const {},
    }) => PuzzleSaveState(
      trayPieceIndexes: tray,
      lockedPieceIndexes: locked,
      loosePiecePositions: loose,
    );

    final complete = state(
      tray: [2, 3],
      locked: [0],
      loose: {1: Vector2.zero()},
    );
    expect(complete.isConsistentFor(4), isTrue);

    expect(state(tray: [0, 1]).isConsistentFor(4), isFalse); // missing pieces
    expect(
      state(tray: [0, 1, 2, 2]).isConsistentFor(4),
      isFalse, // duplicate piece
    );
    expect(
      state(tray: [0, 1, 2, 9]).isConsistentFor(4),
      isFalse, // index out of range
    );
  });

  test('puzzleSaveKey is unique per image and grid size', () {
    final a = puzzleSaveKey(imageId: 'cat', columns: 6, rows: 4);
    final b = puzzleSaveKey(imageId: 'cat', columns: 10, rows: 6);
    final c = puzzleSaveKey(imageId: 'dog', columns: 6, rows: 4);
    expect({a, b, c}, hasLength(3));
  });

  test('parsePuzzleSaveKey round-trips what puzzleSaveKey builds', () {
    expect(
      parsePuzzleSaveKey(
        puzzleSaveKey(imageId: 'misty-harbor', columns: 12, rows: 8),
      ),
      (imageId: 'misty-harbor', columns: 12, rows: 8),
    );
    // Ids are dot-free today, but a future dot must not shift the grid.
    expect(
      parsePuzzleSaveKey(
        puzzleSaveKey(imageId: 'cat.v2', columns: 6, rows: 4),
      ),
      (imageId: 'cat.v2', columns: 6, rows: 4),
    );
  });

  test('keys that do not follow the save format parse as null', () {
    const foreign = [
      'done.cat.6x4', // the completion store's namespace
      'daily.days', // streak data
      'save.cat', // no grid
      'save.cat.6by4',
      'save.cat.x4',
      'save.cat.6x',
      'save..6x4', // empty image id
      'save.cat.99999999999999999999x9', // digits beyond the regex cap
    ];
    for (final key in foreign) {
      expect(parsePuzzleSaveKey(key), isNull, reason: key);
    }
  });

  test('listSavedKeys lists saves and ignores foreign namespaces', () async {
    final store = InMemorySaveStore();
    const state = PuzzleSaveState(
      trayPieceIndexes: [0],
      lockedPieceIndexes: [],
      loosePiecePositions: {},
    );
    await store.save('save.cat.6x4', state);
    await store.save('save.dog.12x8', state);
    await store.save('done.cat.6x4', state); // wrong namespace, never listed

    expect(
      (await store.listSavedKeys())..sort(),
      ['save.cat.6x4', 'save.dog.12x8'],
    );
  });

  test('InMemorySaveStore saves, loads, reports, and deletes', () async {
    final store = InMemorySaveStore();
    const key = 'save.test.2x2';
    final state = PuzzleSaveState(
      trayPieceIndexes: const [0, 1, 2, 3],
      lockedPieceIndexes: const [],
      loosePiecePositions: const {},
    );

    expect(await store.exists(key), isFalse);
    expect(await store.load(key), isNull);

    await store.save(key, state);
    expect(await store.exists(key), isTrue);
    expect((await store.load(key))!.trayPieceIndexes, [0, 1, 2, 3]);

    await store.delete(key);
    expect(await store.exists(key), isFalse);
  });
}
