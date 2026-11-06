// Leaving a running puzzle (back button) must never lose or corrupt its
// save — including mid-settle-animation and after a return-to-tray
// (2026-11-06 phone report; the engine paths proved sound, these pin them).
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

void main() {
  const key = 'save.test-photo.6x4';

  JigsawGame makeGame(
    InMemorySaveStore store, {
    void Function(bool resumed)? onBoardLoaded,
  }) => JigsawGame(
    imageAsset: 'test_photo.jpg',
    columns: 6,
    rows: 4,
    saveStore: store,
    saveKey: key,
    startedDay: '2026-11-06',
    onBoardLoaded: onBoardLoaded,
  );

  Future<void> bootGame(WidgetTester tester, JigsawGame game) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
      await game.progressSaved;
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

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

  Future<(TestGesture, PuzzlePiece)> liftPieceFromTray(
    WidgetTester tester,
    JigsawGame game,
  ) async {
    const trayThumbTouch = Offset(50, 460);
    const liftedTouch = Offset(50, 400);
    final gesture = await tester.startGesture(trayThumbTouch);
    await tester.pump(const Duration(milliseconds: 16));
    await dragTo(tester, gesture, trayThumbTouch, liftedTouch);
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    return (gesture, piece);
  }

  Future<bool?> reopenAndReport(
    WidgetTester tester,
    InMemorySaveStore store,
  ) async {
    bool? resumed;
    final game = makeGame(store, onBoardLoaded: (r) => resumed = r);
    await bootGame(tester, game);
    await tester.pumpWidget(const SizedBox.shrink());
    return resumed;
  }

  testWidgets('A: place a piece, leave, reopen -> resumes', (tester) async {
    final store = InMemorySaveStore();
    final game = makeGame(store);
    await bootGame(tester, game);
    expect(await store.exists(key), isTrue, reason: 'initial fresh save');

    final (gesture, _) = await liftPieceFromTray(tester, game);
    await dragTo(tester, gesture, const Offset(50, 400), const Offset(300, 200));
    await gesture.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.runAsync(() => game.progressSaved);

    final save = await store.load(key);
    expect(save, isNotNull, reason: 'save after settle');
    expect(save!.isConsistentFor(24), isTrue);
    expect(save.loosePiecePositions, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink()); // back = dispose
    expect(await store.exists(key), isTrue, reason: 'save survives leaving');
    expect(await reopenAndReport(tester, store), isTrue);
  });

  testWidgets('B: return piece to tray, leave, reopen -> resumes', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = makeGame(store);
    await bootGame(tester, game);

    final (gesture, piece) = await liftPieceFromTray(tester, game);
    await dragTo(tester, gesture, const Offset(50, 400), const Offset(300, 200));
    await gesture.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Drop it back onto the tray.
    final onTray = Vector2(game.size.x / 2, game.size.y - 20);
    game.movePieceTo(piece, game.camera.globalToLocal(onTray) - piece.size / 2);
    piece.settle();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.runAsync(() => game.progressSaved);

    final save = await store.load(key);
    expect(save, isNotNull);
    expect(save!.isConsistentFor(24), isTrue, reason: 'return-to-tray save');
    expect(save.trayPieceIndexes, hasLength(24));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(await store.exists(key), isTrue);
    expect(await reopenAndReport(tester, store), isTrue);
  });

  testWidgets('C: leave DURING the settle animation -> still resumable', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = makeGame(store);
    await bootGame(tester, game);

    final (gesture, _) = await liftPieceFromTray(tester, game);
    await dragTo(tester, gesture, const Offset(50, 400), const Offset(300, 200));
    await gesture.up();
    // No settle pumps: back immediately, mid-animation.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => game.progressSaved);

    final save = await store.load(key);
    expect(save, isNotNull, reason: 'at least the pre-lift save must remain');
    expect(save!.isConsistentFor(24), isTrue,
        reason: 'mid-settle leave must not corrupt the save');
    expect(await reopenAndReport(tester, store), isTrue);
  });
}
