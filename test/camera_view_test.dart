import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';

import 'test_helpers.dart';

/// Camera rules from the 2026-11-05 phone-test rulings: the board stays put
/// at the fitted view, panning is earned by zooming in, and zooming back out
/// (or the AppBar fit button) snaps the camera home.
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

  testWidgets('resetView returns to the fitted view after zoom and pan', (
    tester,
  ) async {
    final game = await bootGame(tester);
    final fit = game.camera.viewfinder.zoom;
    final home = game.camera.viewfinder.position.clone();
    game.zoomTo(fit * 2.5, Vector2(200, 300));
    game.panBy(Vector2(60, -40));

    game.resetView();
    expect(game.camera.viewfinder.zoom, fit);
    expect(game.camera.viewfinder.position, home);
  });

  testWidgets('the fit-screen AppBar button resets the view', (tester) async {
    MockSharedPreferences().install();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    final fit = game.camera.viewfinder.zoom;
    final home = game.camera.viewfinder.position.clone();
    game.zoomTo(fit * 2, Vector2(100, 100));

    await tester.tap(find.byTooltip('Fit board to screen'));
    await tester.pump();
    expect(game.camera.viewfinder.zoom, fit);
    expect(game.camera.viewfinder.position, home);
  });
}
