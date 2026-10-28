import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

class _DelayedSaveStore extends InMemorySaveStore {
  final requested = Completer<void>();
  final result = Completer<PuzzleSaveState?>();

  @override
  Future<PuzzleSaveState?> load(String key) {
    requested.complete();
    return result.future;
  }
}

void main() {
  late List<ui.Image> generated;
  late ui.ImageEventCallback? previousOnCreate;

  setUp(() {
    generated = [];
    previousOnCreate = ui.Image.onCreate;
  });

  tearDown(() {
    ui.Image.onCreate = previousOnCreate;
  });

  Future<ui.Image> capturePieceImages(
    WidgetTester tester,
    JigsawGame game,
  ) async {
    late ui.Image source;
    // Preload the shared source so the hook captures only game-owned images.
    await tester.runAsync(() async {
      source = await game.images.load('test_photo.jpg');
    });
    ui.Image.onCreate = (image) {
      previousOnCreate?.call(image);
      generated.add(image);
    };
    return source;
  }

  testWidgets('leaving the game disposes its pieces, not the shared source', (
    tester,
  ) async {
    final game = JigsawGame(imageAsset: 'test_photo.jpg', columns: 6, rows: 4);
    final source = await capturePieceImages(tester, game);
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    await tester.pump(const Duration(milliseconds: 16));
    expect(generated.length, 24);
    expect(generated.every((image) => !image.debugDisposed), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(generated.every((image) => image.debugDisposed), isTrue);
    expect(source.debugDisposed, isFalse);
    // Cleanup is safe if the owner receives a repeated disposal request.
    game.onDispose();
  });

  testWidgets('leaving while saves load does not finish setting up the board', (
    tester,
  ) async {
    late _DelayedSaveStore store;
    // Rendering runs outside the fake clock; create its wait signals there too.
    await tester.runAsync(() async {
      store = _DelayedSaveStore();
    });
    var reportedLoaded = false;
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: 6,
      rows: 4,
      saveStore: store,
      saveKey: 'leaving-during-load',
      onBoardLoaded: (_) => reportedLoaded = true,
    );
    final source = await capturePieceImages(tester, game);
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await store.requested.future;
    });
    expect(generated.length, 24);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(generated.every((image) => image.debugDisposed), isTrue);

    store.result.complete(null);
    await tester.runAsync(() => game.loaded);
    expect(reportedLoaded, isFalse);
    expect(game.trayPieceIndexes, isEmpty);
    expect(await store.exists('leaving-during-load'), isFalse);
    expect(source.debugDisposed, isFalse);
  });

  testWidgets(
    'disposal during rasterization releases images that arrive later',
    (tester) async {
      var reportedLoaded = false;
      final game = JigsawGame(
        imageAsset: 'test_photo.jpg',
        columns: 6,
        rows: 4,
        onBoardLoaded: (_) => reportedLoaded = true,
      );
      final source = await capturePieceImages(tester, game);
      final capture = ui.Image.onCreate!;
      ui.Image.onCreate = (image) {
        capture(image);
        // Simulate teardown while toImage futures are still completing.
        if (generated.length == 1) game.onDispose();
      };
      await tester.runAsync(() async {
        await tester.pumpWidget(GameWidget(game: game));
        await game.loaded;
      });
      expect(generated.length, 24);
      expect(generated.every((image) => image.debugDisposed), isTrue);
      expect(reportedLoaded, isFalse);
      expect(game.trayPieceIndexes, isEmpty);
      expect(source.debugDisposed, isFalse);
    },
  );
}
