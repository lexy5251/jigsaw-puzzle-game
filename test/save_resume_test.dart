import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

/// Save & resume behavior: snapshots are written as pieces settle and are
/// restored on boot. Uses the in-memory store, so no platform storage runs.
void main() {
  const key = 'save.test-photo.6x4';

  JigsawGame makeGame(
    InMemorySaveStore store, {
    int columns = 6,
    int rows = 4,
    Future<bool> Function()? onCompleted,
    void Function(bool resumed)? onBoardLoaded,
  }) => JigsawGame(
    imageAsset: 'test_photo.jpg',
    columns: columns,
    rows: rows,
    saveStore: store,
    saveKey: key,
    onCompleted: onCompleted,
    onBoardLoaded: onBoardLoaded,
  );

  Future<void> bootGame(WidgetTester tester, JigsawGame game) async {
    // runAsync lets the real asset load + image decode inside onLoad finish
    // (they happen off the fake test clock).
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
      await game.progressSaved;
    });
    // A few real ticks so queued component additions (tray, board) mount.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Moves a held gesture in small steps, pumping between them.
  Future<void> dragTo(
    WidgetTester tester,
    TestGesture gesture,
    Offset from,
    Offset to,
  ) async {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(from + (to - from) * (i / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Drags a piece out of the tray (test surface is 800x600; the tray starts
  /// at y=492 and the first thumbnail sits around x=10..98).
  Future<(TestGesture, PuzzlePiece)> liftPieceFromTray(
    WidgetTester tester,
    JigsawGame game,
  ) async {
    const trayThumbTouch = Offset(50, 550);
    const liftedTouch = Offset(50, 400);
    final gesture = await tester.startGesture(trayThumbTouch);
    await tester.pump(const Duration(milliseconds: 16));
    await dragTo(tester, gesture, trayThumbTouch, liftedTouch);
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    return (gesture, piece);
  }

  Offset canvasPointFor(JigsawGame game, Vector2 worldTarget) {
    final canvas = game.camera.localToGlobal(worldTarget);
    return Offset(canvas.x, canvas.y);
  }

  testWidgets('a saved game restores locked, loose, and tray pieces', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final savedTrayOrder = [for (var i = 23; i >= 2; i--) i];
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: savedTrayOrder,
        lockedPieceIndexes: const [0],
        loosePiecePositions: {1: Vector2(50, 70)},
      ),
    );

    bool? reportedResumed;
    final game = makeGame(
      store,
      onBoardLoaded: (resumed) {
        reportedResumed = resumed;
      },
    );
    await bootGame(tester, game);

    expect(reportedResumed, isTrue);
    expect(game.progress.lockedCount, 1);
    expect(game.trayPieceIndexes, savedTrayOrder);

    final pieces = game.world.children.whereType<PuzzlePiece>().toList();
    final locked = pieces.singleWhere((piece) => piece.isLocked);
    expect(locked.index, 0);
    expect(locked.position, locked.correctPosition);

    final loose = pieces.singleWhere((piece) => !piece.isLocked);
    expect(loose.index, 1);
    expect(loose.position, Vector2(50, 70));
  });

  testWidgets('a save that does not match the grid is ignored', (tester) async {
    final store = InMemorySaveStore();
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: const [0, 1, 2], // written for a different size
        lockedPieceIndexes: const [],
        loosePiecePositions: const {},
      ),
    );

    bool? reportedResumed;
    final game = makeGame(
      store,
      onBoardLoaded: (resumed) {
        reportedResumed = resumed;
      },
    );
    await bootGame(tester, game);

    expect(reportedResumed, isFalse);
    expect(game.progress.lockedCount, 0);
    expect(game.trayPieceIndexes, hasLength(24));
    expect(game.world.children.whereType<PuzzlePiece>(), isEmpty);
  });

  testWidgets('dropping a piece loose on the board writes a snapshot', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = makeGame(store);
    await bootGame(tester, game);

    final (gesture, piece) = await liftPieceFromTray(tester, game);
    // One piece-width right of the correct spot: settles loose, no snap.
    final target =
        piece.correctPosition + piece.size / 2 + Vector2(piece.size.x, 0);
    await dragTo(
      tester,
      gesture,
      const Offset(50, 400),
      canvasPointFor(game, target),
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    final saved = await store.load(key);
    expect(saved, isNotNull);
    expect(saved!.trayPieceIndexes, hasLength(23));
    expect(saved.lockedPieceIndexes, isEmpty);
    expect(saved.loosePiecePositions, hasLength(1));
    expect(saved.loosePiecePositions.keys.single, piece.index);
  });

  testWidgets('completing the puzzle deletes its save and reports completion', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    var completions = 0;
    // A 1x1 puzzle completes with a single correct drop.
    final game = makeGame(
      store,
      columns: 1,
      rows: 1,
      onCompleted: () async {
        completions++;
        return true;
      },
    );
    await bootGame(tester, game);

    final (gesture, piece) = await liftPieceFromTray(tester, game);
    final target = piece.correctPosition + piece.size / 2;
    await dragTo(
      tester,
      gesture,
      const Offset(50, 400),
      canvasPointFor(game, target),
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    // Give the snap glide (100ms) time to finish and lock the piece.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(game.progress.isComplete, isTrue);
    expect(completions, 1);
    expect(await store.exists(key), isFalse);
  });

  testWidgets('a delayed progress write cannot recreate a completed save', (
    tester,
  ) async {
    final store = _DelayedSaveStore();
    final game = makeGame(
      store,
      columns: 1,
      rows: 1,
      onCompleted: () async => true,
    );
    await bootGame(tester, game);
    final writeGate = Completer<void>();
    store.writeGate = writeGate;
    addTearDown(() {
      if (!writeGate.isCompleted) {
        writeGate.complete();
      }
    });
    game.persistProgress();
    await tester.pump();

    final (gesture, piece) = await liftPieceFromTray(tester, game);
    final target = piece.correctPosition + piece.size / 2;
    await dragTo(
      tester,
      gesture,
      const Offset(50, 400),
      canvasPointFor(game, target),
    );
    await gesture.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(game.progress.isComplete, isTrue);
    expect(await store.exists(key), isTrue);
    writeGate.complete();
    await tester.pump();
    expect(await store.exists(key), isFalse);
  });

  testWidgets(
    'a save written while a piece is still snapping stays resumable',
    (tester) async {
      final store = _RecordingSaveStore();
      // Both pieces loose on the board, ready to be dropped on their spots.
      await store.save(
        key,
        PuzzleSaveState(
          trayPieceIndexes: const [],
          lockedPieceIndexes: const [],
          loosePiecePositions: {0: Vector2(10, 40), 1: Vector2(60, 40)},
        ),
      );
      var completions = 0;
      final game = makeGame(
        store,
        columns: 2,
        rows: 1,
        onCompleted: () async {
          completions++;
          return true;
        },
      );
      await bootGame(tester, game);

      // Drop the second piece while the first one's snap glide (100ms) is
      // still running: the save written when the first piece locks must not
      // already count the gliding one.
      final pieces = game.world.children.whereType<PuzzlePiece>().toList();
      for (final piece in pieces) {
        piece.position.setFrom(piece.correctPosition);
        piece.settle();
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(game.progress.isComplete, isTrue);
      expect(completions, 1);
      for (final snapshot in store.written) {
        expect(snapshot.lockedPieceIndexes, hasLength(lessThan(2)));
      }
      expect(await store.exists(key), isFalse);
    },
  );

  testWidgets('restoring a fully locked save still records the completion', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    // Should never be written, but must self-heal if it ever exists:
    // without a retry the puzzle would stay "in progress" forever.
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: const [],
        lockedPieceIndexes: const [0, 1],
        loosePiecePositions: const {},
      ),
    );
    var completions = 0;
    final game = makeGame(
      store,
      columns: 2,
      rows: 1,
      onCompleted: () async {
        completions++;
        return true;
      },
    );
    await bootGame(tester, game);
    await tester.pump();

    expect(game.progress.isComplete, isTrue);
    expect(completions, 1);
    expect(await store.exists(key), isFalse);
  });

  testWidgets('a late completion cannot delete a newer session save', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: const [],
        lockedPieceIndexes: const [],
        loosePiecePositions: {0: Vector2(25, 30)},
      ),
    );
    final completionGate = Completer<bool>();
    addTearDown(() {
      if (!completionGate.isCompleted) {
        completionGate.complete(true);
      }
    });
    final oldGame = makeGame(
      store,
      columns: 1,
      rows: 1,
      onCompleted: () => completionGate.future,
    );
    await bootGame(tester, oldGame);

    final piece = oldGame.world.children.whereType<PuzzlePiece>().single;
    piece.position.setFrom(piece.correctPosition);
    piece.settle();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(oldGame.progress.isComplete, isTrue);

    // The player reopens the puzzle while the completion record is still
    // being written: the new session takes over the save key.
    final newGame = makeGame(store, columns: 1, rows: 1);
    await bootGame(tester, newGame);
    final newPiece = newGame.world.children.whereType<PuzzlePiece>().single;
    newPiece.position.setValues(40, 50);
    newGame.persistProgress();
    await tester.runAsync(() => newGame.progressSaved);

    // The old session's completion finally lands; it must leave the new
    // session's save alone.
    completionGate.complete(true);
    await tester.pump();
    await tester.pump();

    final saved = await store.load(key);
    expect(saved, isNotNull);
    expect(saved!.loosePiecePositions[0], Vector2(40, 50));
  });
}

class _DelayedSaveStore extends InMemorySaveStore {
  Completer<void>? writeGate;

  @override
  Future<void> save(String key, PuzzleSaveState state) async {
    await writeGate?.future;
    await super.save(key, state);
  }
}

/// Remembers every snapshot written, so tests can check intermediate saves.
class _RecordingSaveStore extends InMemorySaveStore {
  final List<PuzzleSaveState> written = [];

  @override
  Future<void> save(String key, PuzzleSaveState state) {
    written.add(state);
    return super.save(key, state);
  }
}
