import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';

import 'test_helpers.dart';

/// Camera rules from the 2026-11-05 phone-test rulings: the board stays put
/// at the fitted view, panning is earned by zooming in, and zooming back out
/// snaps the camera home (a real resize refits the same way).
void main() {
  Future<JigsawGame> bootGame(WidgetTester tester) async {
    final game = JigsawGame(imageAsset: 'test_photo.jpg', columns: 6, rows: 4);
    // runAsync lets the real asset load + image decode inside onLoad finish.
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    // A few real ticks so queued component additions (tray, board) mount.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  testWidgets('panBy is ignored at the fitted view', (tester) async {
    final game = await bootGame(tester);
    final home = game.camera.viewfinder.position.clone();
    game.panBy(Vector2(120, 80));
    expect(game.camera.viewfinder.position, home);
  });

  testWidgets('zooming in enables panning, clamped at the board margins', (
    tester,
  ) async {
    final game = await bootGame(tester);
    final fit = game.camera.viewfinder.zoom;
    game.zoomTo(fit * 2, Vector2(400, 246));
    expect(game.camera.viewfinder.zoom, fit * 2);

    final before = game.camera.viewfinder.position.clone();
    game.panBy(Vector2(-50, -30));
    final expected = before + Vector2(50, 30) / (fit * 2);
    expect(
      game.camera.viewfinder.position.distanceTo(expected),
      lessThan(1e-6),
    );

    // A second absurd pan moves nothing: the first already hit the clamp.
    game.panBy(Vector2(-1e6, -1e6));
    final clamped = game.camera.viewfinder.position.clone();
    game.panBy(Vector2(-1e6, -1e6));
    expect(game.camera.viewfinder.position, clamped);
  });

  testWidgets('zooming back out snaps the camera home to the fitted view', (
    tester,
  ) async {
    final game = await bootGame(tester);
    final fit = game.camera.viewfinder.zoom;
    final home = game.camera.viewfinder.position.clone();

    game.zoomTo(fit * 3, Vector2(600, 150));
    game.panBy(Vector2(-40, 25));
    expect(game.camera.viewfinder.position, isNot(home));

    // Within the 1% fitted band counts as fitted and recenters exactly.
    game.zoomTo(fit * 1.005, Vector2(600, 150));
    expect(game.camera.viewfinder.zoom, fit);
    expect(game.camera.viewfinder.position, home);

    // Requests below the fit zoom land home too (no zooming out past fit).
    game.zoomTo(fit * 2, Vector2(600, 150));
    game.zoomTo(fit * 0.5, Vector2(600, 150));
    expect(game.camera.viewfinder.zoom, fit);
    expect(game.camera.viewfinder.position, home);
  });

  testWidgets('a same-size relayout keeps the zoomed and panned view', (
    tester,
  ) async {
    final game = await bootGame(tester);
    final fit = game.camera.viewfinder.zoom;
    game.zoomTo(fit * 2, Vector2(400, 246));
    game.panBy(Vector2(-50, -30));
    final view = game.camera.viewfinder.position.clone();

    // GameWidget rebuilds (the board color setState) re-fire onGameResize
    // with an unchanged size — the player's view must survive them.
    game.onGameResize(game.size.clone());
    expect(game.camera.viewfinder.zoom, fit * 2);
    expect(game.camera.viewfinder.position, view);

    // An actual size change still refits the board.
    game.onGameResize(game.size + Vector2(0, 80));
    expect(game.camera.viewfinder.zoom, isNot(fit * 2));
  });

  testWidgets('the fitted view anchors the board at the top', (tester) async {
    final game = await bootGame(tester);
    final trayHeight = game.trayHeightOnScreen.value;
    expect(trayHeight, greaterThan(0));

    // The board's top-left corner on screen: horizontally centered, with
    // exactly the fit margin above it — all slack falls below the board.
    final topLeft = game.camera.localToGlobal(Vector2.zero());
    final available = game.size.y - trayHeight - game.controlRowHeight;
    expect(topLeft.y, closeTo(boardTopMargin(available), 1e-6));
    // Symmetric side margins mean the board is centered.
    final zoom = game.camera.viewfinder.zoom;
    expect(
      topLeft.x,
      closeTo((game.size.x - testPhotoWidth * zoom) / 2, 1e-6),
    );
  });

  testWidgets('zoomInStep ladders fit -> 2x -> 4x and stays at the cap', (
    tester,
  ) async {
    final game = await bootGame(tester);
    final fit = game.camera.viewfinder.zoom;

    game.zoomInStep();
    expect(game.camera.viewfinder.zoom, closeTo(fit * 2, 1e-9));
    game.zoomInStep();
    expect(game.camera.viewfinder.zoom, closeTo(fit * 4, 1e-9));
    game.zoomInStep();
    expect(game.camera.viewfinder.zoom, closeTo(fit * 4, 1e-9));

    // Pinching out still snaps home from a stepped zoom.
    game.zoomTo(fit * 0.5, Vector2(400, 246));
    expect(game.camera.viewfinder.zoom, fit);
  });

  testWidgets('zoomInStep keeps the board center fixed on screen', (
    tester,
  ) async {
    final game = await bootGame(tester);
    // test_photo.jpg world center; its canvas position must not drift as
    // the steps zoom in — aiming anywhere else would shove the
    // top-anchored board off-screen step by step.
    final boardCenter = Vector2(testPhotoWidth / 2, testPhotoHeight / 2);
    final before = game.camera.localToGlobal(boardCenter);

    // Tolerance covers Vector2's float32 rounding; the pre-fix drift this
    // pins against was tens of pixels per step.
    game.zoomInStep();
    expect(
      game.camera.localToGlobal(boardCenter).distanceTo(before),
      lessThan(0.1),
    );
    game.zoomInStep();
    expect(
      game.camera.localToGlobal(boardCenter).distanceTo(before),
      lessThan(0.1),
    );
  });

  testWidgets('zoomInStep before the board loads is a no-op', (tester) async {
    final game = JigsawGame(imageAsset: 'test_photo.jpg', columns: 6, rows: 4);
    game.zoomInStep(); // Menu exists before load; must not throw.
    expect(game.camera.viewfinder.zoom, 1);
  });

  testWidgets('zoomInStep survives a viewport shorter than the band', (
    tester,
  ) async {
    final game = await bootGame(tester);
    // A web window squashed below the tray + control-row reserve: the
    // focal clamp's bounds must stay ordered instead of throwing.
    game.onGameResize(Vector2(300, 60));
    game.zoomInStep();
    expect(game.camera.viewfinder.zoom.isFinite, isTrue);
  });

  testWidgets('the fitted camera rests inside the pan bounds', (tester) async {
    final game = await bootGame(tester);
    // A tall narrow window could anchor the camera past the pan clamp;
    // resting there made the first pinch snap the board to the bound
    // instead of zooming around the fingers.
    game.onGameResize(Vector2(250, 1100));
    final fitted = game.camera.viewfinder.position.clone();
    expect(fitted.y, lessThanOrEqualTo(testPhotoHeight * 1.5));

    // A slight pinch on the viewport center now stays put instead of
    // lurching to the clamp bound.
    final fit = game.camera.viewfinder.zoom;
    game.zoomTo(fit * 1.02, Vector2(125, 550));
    expect(game.camera.viewfinder.position.distanceTo(fitted), lessThan(30));
  });
}
