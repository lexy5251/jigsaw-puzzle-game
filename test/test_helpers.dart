import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Channel-backed preferences with controllable storage failures.
class MockSharedPreferences {
  static const _channel = MethodChannel(
    'plugins.flutter.io/shared_preferences',
  );

  /// Platform keys include the `flutter.` prefix.
  final storage = <String, Object>{};
  int writes = 0;
  Object? readError;

  /// Suites for stores whose records must never be deleted set this false,
  /// so an unexpected `remove` fails loudly instead of passing silently.
  bool allowRemoves = true;

  /// Runs before a set or removal. Return false, throw, or delay to simulate
  /// a failed or pending write without changing the stored data.
  FutureOr<bool> Function(String key)? onWrite;

  /// Call from setUp; the handler and preferences cache are cleared afterwards.
  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.resetStatic();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, _handle);
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      SharedPreferences.resetStatic();
    });
  }

  Future<Object> _handle(MethodCall call) async {
    if (call.method == 'getAll') {
      final error = readError;
      if (error != null) {
        throw error;
      }
      return Map<String, Object>.of(storage);
    }
    if (call.method != 'setString' && call.method != 'remove') {
      throw StateError('Unexpected storage call: ${call.method}');
    }
    if (call.method == 'remove' && !allowRemoves) {
      throw StateError('Unexpected storage call: remove');
    }
    final arguments = call.arguments as Map;
    final key = arguments['key'] as String;
    writes++;
    final write = onWrite;
    if (write != null && !await write(key)) {
      return false;
    }
    if (call.method == 'setString') {
      storage[key] = arguments['value'] as String;
    } else {
      storage.remove(key);
    }
    return true;
  }
}

/// Pumps the selection screen under the app's real theme with a fixed clock.
Future<void> pumpSelectScreen(
  WidgetTester tester, {
  required DateTime Function() clock,
}) {
  return tester.pumpWidget(
    MaterialApp(theme: studioTheme(), home: PuzzleSelectScreen(clock: clock)),
  );
}

/// Scrolls the selection screen until [finder] is fully visible — needed
/// because the daily card can repeat a catalog tile's title above the fold.
/// Tapping stays with the caller: some tests assert semantics first.
Future<void> scrollSelectScreenTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 120,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Loads the real game and advances enough frames to mount its pieces.
Future<JigsawGame> bootGameScreen(
  WidgetTester tester, {
  required PuzzleImage image,
  required PuzzleSize size,
  DateTime Function()? clock,
}) async {
  late JigsawGame game;
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(image: image, size: size, clock: clock),
      ),
    );
    game = tester
        .widget<GameWidget<JigsawGame>>(find.byType(GameWidget<JigsawGame>))
        .game!;
    await game.loaded;
  });
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return game;
}

/// Completes a fixture with one loose piece, then shows the completion card.
Future<void> completePuzzle(WidgetTester tester, JigsawGame game) async {
  game.world.children.whereType<PuzzlePiece>().single.settle();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(game.progress.isComplete, isTrue);
  await tester.pump(const Duration(milliseconds: 950));
  await tester.pump(const Duration(milliseconds: 350));
}
