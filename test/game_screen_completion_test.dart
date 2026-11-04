import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  const image = PuzzleImage(
    id: 'test',
    title: 'Test puzzle',
    categoryId: 'test',
    fileName: 'test_photo.jpg',
  );
  const size = PuzzleSize(label: 'Test', columns: 1, rows: 1);
  const progressKey = 'flutter.save.test.1x1';
  const completionKey = 'flutter.done.test.1x1';
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
    prefs.storage[progressKey] = PuzzleSaveState(
      trayPieceIndexes: const [],
      lockedPieceIndexes: const [],
      loosePiecePositions: {0: Vector2.zero()},
    ).toJsonString();
  });

  testWidgets('keeps progress until completion is stored successfully', (
    tester,
  ) async {
    final completionWrite = Completer<bool>();
    prefs.onWrite = (key) =>
        key == completionKey ? completionWrite.future : true;
    addTearDown(() {
      if (!completionWrite.isCompleted) {
        completionWrite.complete(false);
      }
    });
    final game = await bootGameScreen(tester, image: image, size: size);
    final previousProgress = prefs.storage[progressKey];
    await completePuzzle(tester, game);

    expect(find.text('Puzzle complete!'), findsOneWidget);
    expect(prefs.storage[progressKey], previousProgress);
    expect(prefs.storage.containsKey(completionKey), isFalse);

    completionWrite.complete(true);
    await tester.pump();

    expect(prefs.storage.containsKey(completionKey), isTrue);
    expect(prefs.storage.containsKey(progressKey), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final throwsError in [false, true]) {
    testWidgets(
      'keeps resumable progress when completion ${throwsError ? 'throws' : 'is rejected'}',
      (tester) async {
        prefs.onWrite = (key) {
          if (key != completionKey) {
            return true;
          }
          if (throwsError) {
            throw PlatformException(code: 'write_failed');
          }
          return false;
        };
        final game = await bootGameScreen(tester, image: image, size: size);
        final previousProgress = prefs.storage[progressKey];
        await completePuzzle(tester, game);

        expect(tester.takeException(), isNull);
        expect(prefs.storage[progressKey], previousProgress);
        expect(prefs.storage.containsKey(completionKey), isFalse);
        expect(
          await const SharedPreferencesCompletionStore().isCompleted(
            'done.test.1x1',
          ),
          isFalse,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        SharedPreferences.resetStatic();
        final resumed = await bootGameScreen(tester, image: image, size: size);
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

    final game = await bootGameScreen(tester, image: image, size: size);
    await completePuzzle(tester, game);

    expect(find.text('Puzzle complete!'), findsOneWidget);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving an unfinished puzzle keeps its progress', (
    tester,
  ) async {
    final game = await bootGameScreen(tester, image: image, size: size);
    final piece = game.world.children.whereType<PuzzlePiece>().single;
    piece.position.setValues(25, 30);
    game.persistProgress();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    expect(prefs.storage.containsKey(progressKey), isTrue);
    expect(prefs.storage.containsKey(completionKey), isFalse);
    final saved = PuzzleSaveState.fromJsonString(
      prefs.storage[progressKey] as String,
    )!;
    expect(saved.loosePiecePositions[0], Vector2(25, 30));
  });
}
