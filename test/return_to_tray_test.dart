import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/piece_tray.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

/// Counts drop cues: the bulk sweep must play one for the whole batch.
class _CountingSounds extends SilentGameSounds {
  int drops = 0;

  @override
  void playDrop() => drops++;
}

/// Returning pieces to the tray (2026-11-05 phone request): a lone loose
/// piece dropped over the tray leaves the board and rejoins the strip,
/// while chunks and locked pieces stay on the board.
void main() {
  const key = 'return-tests';
  final offset = Vector2(300, 220);

  Future<JigsawGame> boot(
    WidgetTester tester,
    InMemorySaveStore store, {
    required Map<int, Vector2> loose,
    List<int> locked = const [],
    GameSounds? sounds,
  }) async {
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: [
          for (var i = 0; i < 24; i++)
            if (!loose.containsKey(i) && !locked.contains(i)) i,
        ],
        lockedPieceIndexes: locked,
        loosePiecePositions: loose,
        boardWidth: testPhotoWidth,
      ),
    );
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: 6,
      rows: 4,
      saveStore: store,
      saveKey: key,
      sounds: sounds,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  Map<int, PuzzlePiece> pieces(JigsawGame game) => {
    for (final piece in game.world.children.whereType<PuzzlePiece>())
      piece.index: piece,
  };

  double trayTopOf(JigsawGame game) =>
      game.camera.viewport.children.whereType<PieceTray>().single.position.y;

  /// Releases [piece] with its center resting mid-tray on screen.
  Future<void> dropOnTray(
    WidgetTester tester,
    JigsawGame game,
    PuzzlePiece piece,
  ) async {
    final onTray = Vector2(game.size.x / 2, game.size.y - 20);
    game.movePieceTo(piece, game.camera.globalToLocal(onTray) - piece.size / 2);
    piece.settle();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a lone piece dropped on the tray returns to it', (tester) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});
    expect(game.trayPieceIndexes, hasLength(23));

    await dropOnTray(tester, game, pieces(game)[8]!);

    expect(pieces(game), isEmpty);
    expect(game.trayPieceIndexes, hasLength(24));

    // It must reappear where it was dropped — on-screen, not at the far
    // (possibly scrolled-off) end of the strip. The 800-wide tray shows
    // 10 columns x 2 rows, and the strip is unscrolled.
    final slot = game.visibleTrayPieceIndexes.indexOf(8);
    expect(slot, isNonNegative);
    expect(slot, lessThan(20));

    // The save reflects the return, so a reload cannot resurrect the piece.
    await game.progressSaved;
    final saved = await store.load(key);
    expect(saved!.loosePiecePositions, isEmpty);
    expect(saved.trayPieceIndexes, contains(8));
  });

  testWidgets('a returned piece hides under the active edges-only filter', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    // Piece 8 is an interior piece on a 6x4 board.
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});
    game.setEdgesOnlyFilter(true);

    await dropOnTray(tester, game, pieces(game)[8]!);

    expect(game.trayPieceIndexes, contains(8));
    expect(game.visibleTrayPieceIndexes, isNot(contains(8)));
  });

  testWidgets('a joined chunk dropped on the tray stays on the board', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    // Identical offsets put 0 and 1 at their exact relative positions, so
    // the restore rebuilds them as one chunk.
    final game = await boot(
      tester,
      store,
      loose: {0: grid6x4Home(0) + offset, 1: grid6x4Home(1) + offset},
    );

    await dropOnTray(tester, game, pieces(game)[0]!);

    expect(pieces(game), hasLength(2));
    expect(game.trayPieceIndexes, hasLength(22));
    // The normal drop rules ran instead: the chunk was pushed clear of
    // the tray, so no part of it can hide under the piece strip.
    for (final piece in pieces(game).values) {
      final bottomOnScreen = game.camera.localToGlobal(
        piece.position + piece.size,
      );
      expect(bottomOnScreen.y, lessThanOrEqualTo(trayTopOf(game)));
    }
  });

  testWidgets('a lone piece dropped just inside the tray returns too', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});
    final piece = pieces(game)[8]!;

    // Release with the finger just past the tray's top edge — the return
    // zone starts exactly there now that no control band sits above it.
    final overTray = Vector2(game.size.x / 2, trayTopOf(game) + 8);
    game.movePieceTo(
      piece,
      game.camera.globalToLocal(overTray) - piece.size / 2,
    );
    piece.noteDragPointer(overTray);
    piece.settle();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(pieces(game), isEmpty);
    expect(game.trayPieceIndexes, hasLength(24));
  });

  testWidgets('a restored piece is nudged clear of the tray', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    // Saved below the board (another screen's sorting area): on this
    // surface it would project into the tray, where the piece strip
    // draws above it and would make the piece un-grabbable.
    final game = await boot(
      tester,
      store,
      loose: {8: Vector2(600, testPhotoHeight + 350)},
    );

    final piece = pieces(game)[8]!;
    final bottomOnScreen = game.camera.localToGlobal(
      piece.position + piece.size,
    );
    expect(bottomOnScreen.y, lessThanOrEqualTo(trayTopOf(game)));
  });

  testWidgets('the sweep returns loose singles, keeps chunks and locked', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final sounds = _CountingSounds();
    // 8 and 14 are lone (different offsets, so the neighbors restore
    // unjoined); 0+1 share an offset and restore as one chunk; 5 is locked.
    final game = await boot(
      tester,
      store,
      loose: {
        8: grid6x4Home(8) + offset,
        14: grid6x4Home(14) + Vector2(40, 90),
        0: grid6x4Home(0) + offset,
        1: grid6x4Home(1) + offset,
      },
      locked: [5],
      sounds: sounds,
    );
    expect(game.trayPieceIndexes, hasLength(19));

    game.returnLoosePiecesToTray();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // The chunk and the locked piece stay; both singles left the board.
    expect(pieces(game).keys.toSet(), {0, 1, 5});
    expect(game.trayPieceIndexes, hasLength(21));
    expect(game.trayPieceIndexes, containsAll([8, 14]));
    // One drop cue for the whole batch, not one per piece.
    expect(sounds.drops, 1);

    // The save reflects the sweep, so a reload cannot resurrect the pieces.
    await game.progressSaved;
    final saved = await store.load(key);
    expect(saved!.trayPieceIndexes, containsAll([8, 14]));
    expect(saved.loosePiecePositions.keys.toSet(), {0, 1});
    expect(saved.lockedPieceIndexes, [5]);
  });

  testWidgets('a swept interior piece hides under the edges-only filter', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});
    game.setEdgesOnlyFilter(true);

    game.returnLoosePiecesToTray();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(pieces(game), isEmpty);
    expect(game.trayPieceIndexes, contains(8));
    expect(game.visibleTrayPieceIndexes, isNot(contains(8)));
  });

  testWidgets('a sweep with nothing loose is a silent no-op', (tester) async {
    final store = InMemorySaveStore();
    final sounds = _CountingSounds();
    final game = await boot(tester, store, loose: {}, sounds: sounds);

    game.returnLoosePiecesToTray();
    await tester.pump(const Duration(milliseconds: 16));

    expect(game.trayPieceIndexes, hasLength(24));
    expect(sounds.drops, 0);
  });

  testWidgets('snapping home pulls pieces back out of the reserved band', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});
    final piece = pieces(game)[8]!;
    final fit = game.camera.viewfinder.zoom;
    game.zoomTo(fit * 2, Vector2(400, 246));

    // Park the piece below the board while zoomed in — legal in that view,
    // but inside the reserved band once the camera snaps home. The refit
    // must sweep it clear, or it would sit under the control row's buttons
    // where a tap fires them instead of grabbing the piece.
    game.movePieceTo(piece, Vector2(600, testPhotoHeight + 300));
    game.zoomTo(fit / 2, Vector2(400, 246));

    final bottomOnScreen = game.camera.localToGlobal(
      piece.position + piece.size,
    );
    expect(bottomOnScreen.y, lessThanOrEqualTo(trayTopOf(game)));
  });

  testWidgets('a squashed window never hurls pieces out of reach', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});
    final before = pieces(game)[8]!.position.clone();

    // Drag the window through a height shorter than the reserved band and
    // back: with no usable board area the clearance must stand down — the
    // unbounded nudge used to move pieces thousands of world units up here,
    // and the next save kept it.
    game.onGameResize(Vector2(300, 60));
    game.onGameResize(Vector2(800, 600));

    expect(
      pieces(game)[8]!.position.distanceTo(before),
      lessThan(testPhotoHeight / 2),
    );
  });

  testWidgets('a resize leaves the carried group where the finger holds it', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});
    final piece = pieces(game)[8]!;
    expect(game.beginPieceDrag(piece), isTrue);
    // Hold the piece low, where the clearance sweep would otherwise act.
    game.movePieceTo(piece, Vector2(600, testPhotoHeight - 50.0));
    final held = piece.position.clone();

    game.onGameResize(Vector2(800, 540));

    // The gesture still owns the piece; its own drop re-clears the band.
    expect(piece.position, held);
    game.settlePiece(piece, allowTrayReturn: false);
  });

  testWidgets('a sweep during a tray touch keeps the strip consistent', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: grid6x4Home(8) + offset});

    // Finger 1 rests on the first top-row thumbnail (the 800x600 surface
    // geometry save_resume_test's lift recipe documents).
    const trayThumbTouch = Offset(50, 460);
    final gesture = await tester.startGesture(trayThumbTouch);
    await tester.pump(const Duration(milliseconds: 16));

    // Finger 2 taps the sweep. The model commits at once, but the strip
    // rebuild must wait for the release — rebuilding now would orphan
    // finger 1's selected thumbnail and leave a liftable ghost twin.
    game.returnLoosePiecesToTray();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.trayPieceIndexes, hasLength(24));

    // Finger 1 still lifts its piece — exactly one copy leaves the tray.
    const liftedTouch = Offset(50, 350);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(
        trayThumbTouch + (liftedTouch - trayThumbTouch) * (i / 8),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pieces(game).keys, hasLength(1));
    final lifted = pieces(game).keys.single;
    await gesture.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(pieces(game).keys, [lifted]);
    expect(game.trayPieceIndexes, hasLength(23));
    expect(game.trayPieceIndexes, isNot(contains(lifted)));
    expect(game.visibleTrayPieceIndexes, isNot(contains(lifted)));
    expect(tester.takeException(), isNull);
  });
}
