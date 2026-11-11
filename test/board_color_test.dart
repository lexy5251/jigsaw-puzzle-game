// The board color picker: the options table, the live swap (Flame only
// re-reads backgroundColor() when the GameWidget rebuilds, so the
// DecoratedBox assertion proves the setState path works), persistence into
// the shared settings blob without clobbering its other fields, and the
// color surviving game startup and restart.

import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

import 'test_helpers.dart';

const _settingsKey = 'flutter.settings.v1';

void main() {
  group('boardColorOptions table', () {
    test('six unique options, default pinned to the settings default', () {
      expect(boardColorOptions, hasLength(6));
      expect(
        boardColorOptions.map((option) => option.id).toSet(),
        hasLength(boardColorOptions.length),
      );
      expect(boardColorOptions, contains(defaultBoardColorOption));
      // The sync pin between app_settings.dart (plain string default) and
      // this table.
      expect(defaultBoardColorOption.id, const AppSettings().boardColorId);
      expect(defaultBoardColorOption.background, StudioColors.board);
    });

    test('unknown ids fall back to the default option', () {
      expect(boardColorOptionFor('nope'), defaultBoardColorOption);
      expect(boardColorOptionFor('slate').id, 'slate');
    });
  });

  group('in-game picker', () {
    late MockSharedPreferences prefs;

    setUp(() {
      prefs = MockSharedPreferences()..install();
    });

    // The live Flame game keeps requesting frames, so pumpAndSettle would
    // never settle — sheet and dialog routes are driven with fixed pumps.
    Future<void> pumpRoute(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> letPersistFinish(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    testWidgets('selecting a swatch recolors the board live and persists', (
      tester,
    ) async {
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      expect(game.backgroundColor(), StudioColors.board);

      await tester.tap(find.byTooltip('Board color'));
      await pumpRoute(tester);
      for (final option in boardColorOptions) {
        expect(
          find.bySemanticsLabel('Board color: ${option.label}'),
          findsOneWidget,
        );
      }
      // Exactly one selection check, sitting on the default tan swatch.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(_checkedSwatchColor(tester), StudioColors.board);

      final slate = boardColorOptionFor('slate');
      await tester.tap(find.bySemanticsLabel('Board color: Slate'));
      await pumpRoute(tester);

      expect(game.backgroundColor(), slate.background);
      expect(game.boardOutlineColor, StudioColors.boardOutlineOnDark);
      // The GameWidget's backdrop actually rebuilt — Flame reads
      // backgroundColor() only during the widget build.
      expect(
        find.descendant(
          of: find.byType(GameWidget<JigsawGame>),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration == BoxDecoration(color: slate.background),
          ),
        ),
        findsAtLeastNWidgets(1),
      );
      // The marker moved and the sheet stayed open for live comparison.
      expect(_checkedSwatchColor(tester), slate.background);
      expect(find.text('Board color'), findsOneWidget);

      await letPersistFinish(tester);
      final saved = jsonDecode(prefs.storage[_settingsKey]! as String);
      expect(saved['boardColorId'], 'slate');

      // The scrim dismisses the sheet.
      await tester.tapAt(const Offset(10, 10));
      await pumpRoute(tester);
      expect(find.text('Board color'), findsNothing);
    });

    testWidgets('a color save keeps the blob\'s other settings', (
      tester,
    ) async {
      prefs.storage[_settingsKey] = const AppSettings(
        effectsVolume: 0.4,
        ghostPreviewDefault: true,
      ).toJsonString();
      await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );

      await tester.tap(find.byTooltip('Board color'));
      await pumpRoute(tester);
      await tester.tap(find.bySemanticsLabel('Board color: Charcoal'));
      await letPersistFinish(tester);

      final saved = AppSettings.fromJsonString(
        prefs.storage[_settingsKey]! as String,
      );
      expect(saved.boardColorId, 'charcoal');
      expect(saved.effectsVolume, 0.4);
      expect(saved.ghostPreviewDefault, isTrue);
    });

    testWidgets('the stored choice colors the board from startup', (
      tester,
    ) async {
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        settings: const AppSettings(boardColorId: 'charcoal'),
      );
      expect(game.backgroundColor(), boardColorOptionFor('charcoal').background);
    });

    testWidgets('an unknown stored id degrades to the default tan', (
      tester,
    ) async {
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
        settings: const AppSettings(boardColorId: 'retired-color'),
      );
      expect(game.backgroundColor(), StudioColors.board);
    });

    testWidgets('restart boots the fresh game with the picked color', (
      tester,
    ) async {
      await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );

      await tester.tap(find.byTooltip('Board color'));
      await pumpRoute(tester);
      await tester.tap(find.bySemanticsLabel('Board color: Slate'));
      await pumpRoute(tester);
      await tester.tapAt(const Offset(10, 10));
      await pumpRoute(tester);

      final gameBeforeRestart = currentGame(tester);
      await tester.tap(find.byTooltip('Restart puzzle'));
      await pumpRoute(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Start over'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        // Let the drain + delete futures complete, then await the new board.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        await currentGame(tester).loaded;
      });
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final freshGame = currentGame(tester);
      expect(identical(freshGame, gameBeforeRestart), isFalse);
      expect(
        freshGame.backgroundColor(),
        boardColorOptionFor('slate').background,
      );
    });

    testWidgets('picking a color keeps the zoomed-in view', (tester) async {
      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      final fit = game.camera.viewfinder.zoom;
      game.zoomTo(fit * 2, Vector2(200, 200));
      final view = game.camera.viewfinder.position.clone();

      await tester.tap(find.byTooltip('Board color'));
      await pumpRoute(tester);
      await tester.tap(find.bySemanticsLabel('Board color: Slate'));
      await pumpRoute(tester);

      // The color-swap setState rebuilds the GameWidget with an unchanged
      // size — the camera must not refit back to the fitted view.
      expect(game.camera.viewfinder.zoom, fit * 2);
      expect(game.camera.viewfinder.position, view);
      await letPersistFinish(tester);
    });

    testWidgets('enlarged text scrolls the sheet instead of overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final game = await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      await tester.tap(find.byTooltip('Board color'));
      await pumpRoute(tester);
      expect(tester.takeException(), isNull); // no RenderFlex overflow

      // Swatches pushed past the sheet's height cap scroll into reach.
      final slate = find.bySemanticsLabel('Board color: Slate');
      await tester.ensureVisible(slate);
      await tester.pump();
      await tester.tap(slate);
      await pumpRoute(tester);
      expect(game.backgroundColor(), boardColorOptionFor('slate').background);
      await letPersistFinish(tester);
    });

    testWidgets('the sheet opens without a scrim and still dismisses', (
      tester,
    ) async {
      await bootGameScreen(
        tester,
        image: singlePieceImage,
        size: singlePieceSize,
      );
      await tester.tap(find.byTooltip('Board color'));
      await pumpRoute(tester);

      // Comparing swatches against the live board only works if the barrier
      // doesn't darken it.
      final barrier = tester.widget<ModalBarrier>(
        find.byType(ModalBarrier).last,
      );
      expect(barrier.color, anyOf(isNull, Colors.transparent));

      // The invisible barrier still catches an outside tap.
      await tester.tapAt(const Offset(10, 10));
      await pumpRoute(tester);
      expect(find.text('Board color'), findsNothing);
    });
  });
}

/// The fill of the swatch currently marked with the selection check.
Color _checkedSwatchColor(WidgetTester tester) {
  // Ancestors are visited nearest-first, so `.first` is the swatch's own
  // Stack, not the screen-level one.
  final swatchStack = find
      .ancestor(of: find.byIcon(Icons.check), matching: find.byType(Stack))
      .first;
  final swatch = tester.widget<PaintedSwatch>(
    find.descendant(of: swatchStack, matching: find.byType(PaintedSwatch)),
  );
  return swatch.color;
}
