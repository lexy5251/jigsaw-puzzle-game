// Returning a piece to the tray with a real gesture (2026-11-08 phone
// request, issue #13): the piece must ride under the finger all the way into
// the tray, the FINGER decides the return (not the piece's center), the
// landing animates instead of swapping in the same frame, and a cancelled
// gesture never counts as a tray drop.

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/piece_tray.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

void main() {
  const key = 'return-follow-tests';
  const width = 1600 / 6;
  const height = 1067 / 4;
  Vector2 home(int index) => Vector2(index % 6 * width, index ~/ 6 * height);

  Future<JigsawGame> boot(
    WidgetTester tester,
    InMemorySaveStore store, {
    required Map<int, Vector2> loose,
  }) async {
    await store.save(
      key,
      PuzzleSaveState(
        trayPieceIndexes: [
          for (var i = 0; i < 24; i++)
            if (!loose.containsKey(i)) i,
        ],
        lockedPieceIndexes: const [],
        loosePiecePositions: loose,
      ),
    );
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: 6,
      rows: 4,
      saveStore: store,
      saveKey: key,
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

  PuzzlePiece? pieceOf(JigsawGame game, int index) => game.world.children
      .whereType<PuzzlePiece>()
      .where((piece) => piece.index == index)
      .firstOrNull;

  PieceTray trayOf(JigsawGame game) =>
      game.camera.viewport.children.whereType<PieceTray>().single;

  Vector2 centerOnScreen(JigsawGame game, PuzzlePiece piece) =>
      game.camera.localToGlobal(piece.position + piece.size / 2);

  /// Drags with a simulated finger from [from] to [to] in small steps and
  /// returns the still-open gesture.
  Future<TestGesture> dragTo(
    WidgetTester tester,
    Vector2 from,
    Vector2 to,
  ) async {
    final gesture = await tester.startGesture(Offset(from.x, from.y));
    await tester.pump(const Duration(milliseconds: 16));
    const steps = 10;
    final step = (to - from) / steps.toDouble();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(step.x, step.y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets('a piece rides under the finger into the tray and returns only '
      'on release, with an animated landing', (tester) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: home(8)});
    final piece = pieceOf(game, 8)!;
    final tray = trayOf(game);
    final trayTop = tray.position.y;

    final start = centerOnScreen(game, piece);
    final target = Vector2(game.size.x / 2, trayTop + tray.size.y / 2);
    final gesture = await tester.startGesture(Offset(start.x, start.y));
    await tester.pump(const Duration(milliseconds: 16));

    const steps = 10;
    final step = (target - start) / steps.toDouble();
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(Offset(step.x, step.y));
      await tester.pump(const Duration(milliseconds: 16));
      final live = pieceOf(game, 8);
      expect(live, isNotNull, reason: 'must stay on the board mid-drag');
      // Grabbed at its center, so the center must track the finger exactly.
      final center = centerOnScreen(game, live!);
      final finger = start + step * i.toDouble();
      expect(center.distanceTo(finger), lessThan(0.01));
    }

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    // The model commits at release: board empty, tray and save updated.
    expect(pieceOf(game, 8), isNull);
    expect(game.trayPieceIndexes, contains(8));
    await game.progressSaved;
    final saved = await store.load(key);
    expect(saved!.loosePiecePositions, isEmpty);
    expect(saved.trayPieceIndexes, contains(8));

    // The landing is animated: the slot stays blank while the flight runs,
    // then reveals the thumbnail.
    expect(tray.landingPieceIndex, 8);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tray.landingPieceIndex, isNull);
  });

  testWidgets('the finger decides: releasing above the tray keeps the piece '
      'on the board even when its center hangs over the tray', (tester) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: home(8)});
    final piece = pieceOf(game, 8)!;
    final trayTop = trayOf(game).position.y;

    // Grab the piece near its TOP edge, so its center hangs well below the
    // finger, then stop with the finger just above the tray: the center is
    // inside the tray band, the finger is not.
    final grab = game.camera.localToGlobal(
      piece.position + Vector2(piece.size.x / 2, piece.size.y * 0.1),
    );
    final halfPieceOnScreen =
        piece.size.y / 2 * game.camera.viewfinder.zoom;
    final fingerEnd = Vector2(game.size.x / 2, trayTop - 10);
    final gesture = await dragTo(tester, grab, fingerEnd);

    final carried = pieceOf(game, 8)!;
    expect(
      centerOnScreen(game, carried).y,
      greaterThan(trayTop),
      reason: 'the setup must hang the center over the tray '
          '(half piece on screen: $halfPieceOnScreen)',
    );

    await gesture.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(pieceOf(game, 8), isNotNull);
    expect(game.trayPieceIndexes, isNot(contains(8)));
    // The normal drop rules ran: the piece was pushed clear of the tray.
    final settled = pieceOf(game, 8)!;
    final bottom = game.camera.localToGlobal(settled.position + settled.size);
    expect(bottom.y, lessThan(trayTop));
  });

  testWidgets('a cancelled gesture never returns the piece to the tray', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: home(8)});
    final piece = pieceOf(game, 8)!;
    final tray = trayOf(game);

    final start = centerOnScreen(game, piece);
    final midTray = Vector2(
      game.size.x / 2,
      tray.position.y + tray.size.y / 2,
    );
    final gesture = await dragTo(tester, start, midTray);

    // The system takes the pointer away (e.g. palm rejection near the
    // screen's bottom edge) — not a deliberate drop.
    await gesture.cancel();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(pieceOf(game, 8), isNotNull);
    expect(game.trayPieceIndexes, isNot(contains(8)));
    final settled = pieceOf(game, 8)!;
    final bottom = game.camera.localToGlobal(settled.position + settled.size);
    expect(bottom.y, lessThan(tray.position.y));
  });

  testWidgets('a pinch mid-drag does not freeze the finger: releasing above '
      'the tray keeps the piece on the board', (tester) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: home(8)});
    final tray = trayOf(game);
    final trayTop = tray.position.y;

    // Carry the piece until the finger is over the tray band.
    final start = centerOnScreen(game, pieceOf(game, 8)!);
    final midTray = Vector2(game.size.x / 2, trayTop + tray.size.y / 2);
    final drag = await dragTo(tester, start, midTray);

    // A second finger lands and spreads: a pinch (scale gesture) starts and
    // freezes piece movement.
    final pinch = await tester.startGesture(const Offset(150, 100));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 4; i++) {
      await pinch.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.isScaling, isTrue);

    // The carried finger retreats well above the tray during the pinch,
    // then releases there.
    const steps = 6;
    final retreat = Vector2(midTray.x, trayTop - 120);
    final step = (retreat - midTray) / steps.toDouble();
    for (var i = 0; i < steps; i++) {
      await drag.moveBy(Offset(step.x, step.y));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await pinch.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // The release decision used the finger's real position, not the stale
    // over-tray point recorded before the pinch began.
    expect(pieceOf(game, 8), isNotNull);
    expect(game.trayPieceIndexes, isNot(contains(8)));
  });

  testWidgets('the landing flight follows the strip when it scrolls '
      'mid-flight', (tester) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: home(8)});
    final tray = trayOf(game);

    // Drop the piece into the tray; the landing flight starts.
    final start = centerOnScreen(game, pieceOf(game, 8)!);
    final midTray = Vector2(
      game.size.x / 2,
      tray.position.y + tray.size.y / 2,
    );
    final drop = await dragTo(tester, start, midTray);
    await drop.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tray.landingPieceIndex, 8);
    final targetBefore = tray.activeFlightTarget!;

    // A second finger scrolls the strip while the flight is still airborne.
    final scroll = await tester.startGesture(
      Offset(game.size.x - 60, tray.position.y + tray.size.y / 2),
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 2; i++) {
      await scroll.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tray.scrollOffset, greaterThan(0));
    expect(tray.landingPieceIndex, 8, reason: 'flight must still be airborne');

    // The flight target tracked the scrolled slot, not the stale rect.
    final slot = tray.visiblePieceIndexes.indexOf(8);
    final slotPosition = tray.thumbnailPositions[slot];
    final tracked = tray.activeFlightTarget!;
    expect(tracked.left, closeTo(slotPosition.x - tray.scrollOffset, 0.01));
    expect(tracked.top, closeTo(slotPosition.y, 0.01));
    expect(tracked.left, isNot(closeTo(targetBefore.left, 0.01)));

    await scroll.up();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tray.landingPieceIndex, isNull);
  });

  testWidgets('lifting the landing slot mid-flight lands the flight at once '
      'instead of flying a ghost', (tester) async {
    final store = InMemorySaveStore();
    final game = await boot(tester, store, loose: {8: home(8)});
    final tray = trayOf(game);
    final trayTop = tray.position.y;

    final start = centerOnScreen(game, pieceOf(game, 8)!);
    final midTray = Vector2(game.size.x / 2, trayTop + tray.size.y / 2);
    final drop = await dragTo(tester, start, midTray);
    await drop.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tray.landingPieceIndex, 8);

    // Grab the (blank) landing slot and lift it back out before the flight
    // lands.
    final slot = tray.visiblePieceIndexes.indexOf(8);
    final slotPosition = tray.thumbnailPositions[slot];
    final grabPoint = Offset(
      tray.position.x +
          slotPosition.x -
          tray.scrollOffset +
          tray.thumbnailSize.x / 2,
      tray.position.y + slotPosition.y + tray.thumbnailSize.y / 2,
    );
    final lift = await tester.startGesture(grabPoint);
    await tester.pump(const Duration(milliseconds: 16));
    await lift.moveBy(Offset(0, trayTop - 80 - grabPoint.dy));
    await tester.pump(const Duration(milliseconds: 16));
    await lift.moveBy(const Offset(0, -5));
    await tester.pump(const Duration(milliseconds: 16));

    // The piece is back on the board and the flight stopped immediately.
    expect(pieceOf(game, 8), isNotNull);
    expect(game.trayPieceIndexes, isNot(contains(8)));
    expect(tray.landingPieceIndex, isNull);
    expect(tray.activeFlightTarget, isNull);

    await lift.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pieceOf(game, 8), isNotNull);
  });

  testWidgets('a return hidden by the edges-only filter still clears its '
      'landing state', (tester) async {
    final store = InMemorySaveStore();
    // Piece 8 is an interior piece on a 6x4 board.
    final game = await boot(tester, store, loose: {8: home(8)});
    game.setEdgesOnlyFilter(true);
    final tray = trayOf(game);

    final start = centerOnScreen(game, pieceOf(game, 8)!);
    final midTray = Vector2(
      game.size.x / 2,
      tray.position.y + tray.size.y / 2,
    );
    final gesture = await dragTo(tester, start, midTray);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    expect(game.trayPieceIndexes, contains(8));
    expect(game.visibleTrayPieceIndexes, isNot(contains(8)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tray.landingPieceIndex, isNull);
  });
}
