import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const image = PuzzleImage(
    id: 'test',
    title: 'Test puzzle',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  );
  const size = PuzzleSize(label: 'Test', columns: 1, rows: 1);
  const progressKey = 'flutter.save.test.1x1';
  const completionKey = 'flutter.done.test.1x1';
  late Map<String, Object> storage;
  Completer<bool>? completionWrite;
  var rejectCompletion = false;
  var throwOnCompletion = false;

  setUp(() {
    SharedPreferences.resetStatic();
    storage = {
      progressKey: PuzzleSaveState(
        trayPieceIndexes: const [],
        lockedPieceIndexes: const [],
        loosePiecePositions: {0: Vector2.zero()},
      ).toJsonString(),
    };
    completionWrite = null;
    rejectCompletion = false;
    throwOnCompletion = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        return Map<String, Object>.of(storage);
      }
      final arguments = call.arguments as Map;
      final key = arguments['key'] as String;
      if (call.method == 'setString') {
        if (key == completionKey) {
          if (throwOnCompletion) {
            throw PlatformException(code: 'write_failed');
          }
          if (rejectCompletion ||
              (completionWrite != null && !await completionWrite!.future)) {
            return false;
          }
        }
        storage[key] = arguments['value'] as String;
        return true;
      }
      if (call.method == 'remove') {
        storage.remove(key);
        return true;
      }
      throw StateError('Unexpected storage call: ${call.method}');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
  });

  Future<JigsawGame> boot(WidgetTester tester) async {
    late JigsawGame game;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GameScreen(image: image, size: size),
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

  Future<void> completePuzzle(WidgetTester tester, JigsawGame game) async {
    game.world.children.whereType<PuzzlePiece>().single.settle();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.progress.isComplete, isTrue);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('keeps progress until completion is stored successfully', (
    tester,
  ) async {
    completionWrite = Completer<bool>();
    addTearDown(() {
      if (!completionWrite!.isCompleted) {
        completionWrite!.complete(false);
      }
    });
    final game = await boot(tester);
    final previousProgress = storage[progressKey];
    await completePuzzle(tester, game);

    expect(find.text('Puzzle complete!'), findsOneWidget);
    expect(storage[progressKey], previousProgress);
    expect(storage.containsKey(completionKey), isFalse);

    completionWrite!.complete(true);
    await tester.pump();

    expect(storage.containsKey(completionKey), isTrue);
    expect(storage.containsKey(progressKey), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final throwsError in [false, true]) {
    testWidgets(
      'keeps resumable progress when completion ${throwsError ? 'throws' : 'is rejected'}',
      (tester) async {
        throwOnCompletion = throwsError;
        rejectCompletion = !throwsError;
        final game = await boot(tester);
        final previousProgress = storage[progressKey];
        await completePuzzle(tester, game);

        expect(tester.takeException(), isNull);
        expect(storage[progressKey], previousProgress);
        expect(storage.containsKey(completionKey), isFalse);
        expect(
          await const SharedPreferencesCompletionStore().isCompleted(
            'done.test.1x1',
          ),
          isFalse,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        SharedPreferences.resetStatic();
        final resumed = await boot(tester);
        expect(resumed.progress.isComplete, isFalse);
        expect(resumed.world.children.whereType<PuzzlePiece>(), hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('the completion card fits on a small landscape screen', (
    tester,
  ) async {
    // Small phone in landscape; the card used to overflow here.
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = await boot(tester);
    await completePuzzle(tester, game);

    expect(find.text('Puzzle complete!'), findsOneWidget);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving an unfinished puzzle keeps its progress', (
    tester,
  ) async {
    final game = await boot(tester);
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    piece.position.setValues(25, 30);
    game.persistProgress();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    expect(storage.containsKey(progressKey), isTrue);
    expect(storage.containsKey(completionKey), isFalse);
    final saved = PuzzleSaveState.fromJsonString(
      storage[progressKey] as String,
    )!;
    expect(saved.loosePiecePositions[0], Vector2(25, 30));
  });
}
