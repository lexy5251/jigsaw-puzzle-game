// The top bar's Options (…) menu: it gathers the board colors, the step
// zoom, and the restart entry that used to be separate app-bar buttons.
// Board-color behavior itself is covered in board_color_test; this suite
// pins the menu's structure and its stay-open rules.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

import 'test_helpers.dart';

void main() {
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
  });

  testWidgets('the menu lists board colors, zoom, and restart', (
    tester,
  ) async {
    await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    expect(find.text('Zoom in'), findsNothing);

    await openOptionsMenu(tester);

    expect(find.text('Board color'), findsOneWidget);
    for (final option in boardColorOptions) {
      expect(
        find.bySemanticsLabel('Board color: ${option.label}'),
        findsOneWidget,
      );
    }
    expect(find.text('Zoom in'), findsOneWidget);
    expect(startOverMenuItem, findsOneWidget);
  });

  testWidgets('Zoom in steps the camera and keeps the menu open', (
    tester,
  ) async {
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    final fit = game.camera.viewfinder.zoom;

    await openOptionsMenu(tester);
    await tester.tap(find.text('Zoom in'));
    await tester.pump();
    expect(game.camera.viewfinder.zoom, closeTo(fit * 2, 1e-9));
    // Still open: repeat taps must not need reopening the menu.
    expect(find.text('Zoom in'), findsOneWidget);

    await tester.tap(find.text('Zoom in'));
    await tester.pump();
    expect(game.camera.viewfinder.zoom, closeTo(fit * 4, 1e-9));
    await tester.tap(find.text('Zoom in'));
    await tester.pump();
    expect(game.camera.viewfinder.zoom, closeTo(fit * 4, 1e-9)); // Capped.
  });

  testWidgets('Start over opens the confirm dialog; declining returns', (
    tester,
  ) async {
    prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
        .toJsonString();
    final game = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );

    await openRestartDialog(tester);

    expect(find.text('Start over?'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await pumpRoute(tester);

    expect(find.text('Start over?'), findsNothing);
    expect(identical(currentGame(tester), game), isTrue);
  });

  testWidgets('system back closes the menu instead of leaving the puzzle', (
    tester,
  ) async {
    final route = await pushGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    await openOptionsMenu(tester);
    expect(find.text('Zoom in'), findsOneWidget);

    // Android back reaches the route, not the menu overlay — the screen's
    // PopScope must swallow the pop and close the menu instead.
    await tester.binding.handlePopRoute();
    await pumpRoute(tester);
    expect(find.text('Zoom in'), findsNothing);
    expect(route.popped, isFalse);

    // With the menu closed, back leaves the puzzle normally again.
    await tester.binding.handlePopRoute();
    await pumpRoute(tester);
    expect(route.popped, isTrue);
  });

  testWidgets('the menu fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    await openOptionsMenu(tester);
    expect(tester.takeException(), isNull); // No overflow.

    // Every entry stays reachable (scrolling into view when needed).
    for (final label in ['Board color', 'Zoom in', 'Start over']) {
      await tester.ensureVisible(find.text(label));
      await tester.pump();
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
  });
}
