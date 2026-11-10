import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

class _FakeSounds implements GameSounds {
  int preloads = 0;
  int disposals = 0;

  @override
  Future<void> preload() async => preloads++;
  @override
  Future<void> dispose() async => disposals++;
  @override
  void playDrop() {}
  @override
  void playSnap() {}
  @override
  void playComplete() {}
}

void main() {
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
    prefs.storage[singlePieceProgressKey] = singleLoosePieceSave()
        .toJsonString();
  });

  Future<void> confirmRestart(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Restart puzzle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Start over'));
    await tester.pump();
  }

  Future<JigsawGame> finishRestart(
    WidgetTester tester,
    JigsawGame previous,
  ) async {
    // pump flushes the storage futures; image decoding needs runAsync.
    await tester.pump();
    final game = currentGame(tester);
    expect(identical(game, previous), isFalse);
    await tester.runAsync(() async {
      await game.loaded;
      await game.progressSaved;
    });
    await tester.pump(const Duration(milliseconds: 250));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  void expectFreshSave() {
    final saved = PuzzleSaveState.fromJsonString(
      prefs.storage[singlePieceProgressKey]! as String,
    )!;
    expect(saved.trayPieceIndexes, [0]);
    expect(saved.loosePiecePositions, isEmpty);
  }

  testWidgets('restart releases old textures and gives each run fresh audio', (
    tester,
  ) async {
    final sounds = <_FakeSounds>[];
    final old = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
      soundsFactory: () {
        final audio = _FakeSounds();
        sounds.add(audio);
        return audio;
      },
    );
    final texture = old.world.children
        .whereType<PuzzlePiece>()
        .single
        .sprite!
        .image;
    final source = await tester.runAsync(
      () => old.images.load(singlePieceImage.fileName),
    );

    await confirmRestart(tester);
    final next = await finishRestart(tester, old);
    expect(texture.debugDisposed, isTrue);
    expect(source!.debugDisposed, isFalse);
    expect(sounds, hasLength(2));
    expect(sounds[0].disposals, 1);
    expect(sounds[1].disposals, 0);
    expect(sounds[1].preloads, 1);

    await confirmRestart(tester);
    await finishRestart(tester, next);
    expect(sounds, hasLength(3));
    expect(sounds.map((audio) => audio.disposals), [1, 1, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sounds.map((audio) => audio.disposals), [1, 1, 1]);
  });

  testWidgets('late drops cannot save while the restart deletion is pending', (
    tester,
  ) async {
    final old = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    final piece = old.world.children.whereType<PuzzlePiece>().single;
    final deleteGate = Completer<bool>();
    addTearDown(() {
      if (!deleteGate.isCompleted) deleteGate.complete(true);
    });
    var writes = 0;
    prefs.onWrite = (key) {
      if (key == singlePieceProgressKey && ++writes == 1) {
        return deleteGate.future;
      }
      return true;
    };

    await confirmRestart(tester);
    await tester.pump(const Duration(milliseconds: 250));
    expect(writes, 1);
    expect(identical(currentGame(tester), old), isTrue);
    expect(old.paused, isTrue);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.replay))
          .onPressed,
      isNull,
    );

    // A finger that was already holding a piece can still deliver a drop.
    piece.position.setValues(25, 30);
    piece.settle();
    old.persistProgress();
    await tester.pump();
    expect(writes, 1);

    deleteGate.complete(true);
    final next = await finishRestart(tester, old);
    expect(next.trayPieceIndexes, [0]);
    expect(find.bySemanticsLabel('Puzzle board, new puzzle'), findsOneWidget);
    expectFreshSave();
  });

  testWidgets('restart drains already queued saves before clearing progress', (
    tester,
  ) async {
    final old = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    final writeGate = Completer<bool>();
    addTearDown(() {
      if (!writeGate.isCompleted) writeGate.complete(true);
    });
    var writes = 0;
    prefs.onWrite = (key) {
      if (key == singlePieceProgressKey && ++writes == 1) {
        return writeGate.future;
      }
      return true;
    };
    old.persistProgress();
    old.persistProgress();
    await tester.pump();

    await confirmRestart(tester);
    expect(writes, 1);
    expect(identical(currentGame(tester), old), isTrue);
    // This request must not extend the queue after restart has begun.
    old.persistProgress();
    writeGate.complete(true);
    await finishRestart(tester, old);
    expect(writes, 4); // Two queued saves, restart delete, fresh-board save.
    expectFreshSave();
  });

  testWidgets('restart cancels the previous run completion card', (
    tester,
  ) async {
    final old = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    await completeBoard(tester, old);
    expect(find.textContaining('no timer, no score'), findsNothing);

    await confirmRestart(tester);
    final next = await finishRestart(tester, old);
    expect(next.progress.isComplete, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('no timer, no score'), findsNothing);
  });

  testWidgets('restart waits for a completion delete already in flight', (
    tester,
  ) async {
    final old = await bootGameScreen(
      tester,
      image: singlePieceImage,
      size: singlePieceSize,
    );
    final deleteGate = Completer<bool>();
    addTearDown(() {
      if (!deleteGate.isCompleted) deleteGate.complete(true);
    });
    var deleting = false;
    prefs.onWrite = (key) {
      if (key == singlePieceProgressKey &&
          !deleting &&
          prefs.storage.containsKey(singlePieceCompletionKey)) {
        deleting = true;
        return deleteGate.future;
      }
      return true;
    };
    // Complete the board but stay inside completionRevealDelay: once the
    // card is up it blurs out the app bar, so this race can only start
    // from a restart requested before the reveal.
    await completeBoard(tester, old);
    expect(deleting, isTrue);

    await confirmRestart(tester);
    expect(identical(currentGame(tester), old), isTrue);
    deleteGate.complete(true);
    await finishRestart(tester, old);
    expectFreshSave();
  });
}
