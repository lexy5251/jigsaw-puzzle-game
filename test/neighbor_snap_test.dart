import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

class _Sounds implements GameSounds {
  int snaps = 0;
  int drops = 0;
  int completes = 0;
  @override
  Future<void> preload() async {}
  @override
  Future<void> dispose() async {}
  @override
  void playSnap() => snaps++;
  @override
  void playDrop() => drops++;
  @override
  void playComplete() => completes++;
}

void main() {
  const key = 'neighbor-tests';
  const width = 1600 / 6;
  const height = 1067 / 4;
  Vector2 home(int index) => Vector2(index % 6 * width, index ~/ 6 * height);
  Vector2 offset = Vector2(300, 220);

  Future<JigsawGame> boot(
    WidgetTester tester,
    InMemorySaveStore store, {
    Map<int, Vector2>? loose,
    GameSounds? sounds,
    int columns = 6,
    int rows = 4,
    Future<bool> Function()? onCompleted,
  }) async {
    if (loose != null) {
      await store.save(
        key,
        PuzzleSaveState(
          trayPieceIndexes: [
            for (var i = 0; i < columns * rows; i++)
              if (!loose.containsKey(i)) i,
          ],
          lockedPieceIndexes: const [],
          loosePiecePositions: loose,
        ),
      );
    }
    final game = JigsawGame(
      imageAsset: 'test_photo.jpg',
      columns: columns,
      rows: rows,
      saveStore: store,
      saveKey: key,
      sounds: sounds,
      onCompleted: onCompleted,
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

  Map<int, PuzzlePiece> pieces(JigsawGame game) => {
    for (final piece in game.world.children.whereType<PuzzlePiece>())
      piece.index: piece,
  };

  Offset canvas(JigsawGame game, Vector2 world) {
    final position = game.camera.localToGlobal(world);
    return Offset(position.x, position.y);
  }

  Future<void> drag(
    WidgetTester tester,
    TestGesture gesture,
    Offset from,
    Offset to,
  ) async {
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(from + (to - from) * (i / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> finishSettle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void expectJoined(PuzzlePiece a, PuzzlePiece b) {
    expect(
      (a.position - b.position).distanceTo(
        a.correctPosition - b.correctPosition,
      ),
      lessThan(0.001),
    );
  }

  testWidgets(
    'board drop joins exactly, clicks once, and saves the old schema',
    (tester) async {
      final store = InMemorySaveStore();
      final sounds = _Sounds();
      final game = await boot(
        tester,
        store,
        sounds: sounds,
        loose: {0: home(0) + offset, 1: home(1) + offset + Vector2(120, 0)},
      );
      final p = pieces(game);
      final start = canvas(game, p[1]!.position + p[1]!.size / 2);
      final gesture = await tester.startGesture(start);
      await drag(
        tester,
        gesture,
        start,
        canvas(game, home(1) + offset + Vector2(20, 0) + p[1]!.size / 2),
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(p[1]!.isSettling, isTrue);
      expectJoined(p[0]!, p[1]!);
      expect(game.progress.lockedCount, 0);
      await game.progressSaved;
      final saved = (await store.load(key))!;
      expect(saved.isConsistentFor(24), isTrue);
      expect((jsonDecode(saved.toJsonString()) as Map).keys.toSet(), {
        'tray',
        'locked',
        'loose',
      });
      expect(
        saved.loosePiecePositions[1]!.distanceTo(p[1]!.position),
        lessThan(0.001),
      );

      await finishSettle(tester);
      expect(sounds.snaps, 1);
      expect(sounds.drops, 0);
      expect(
        p.values.every((piece) => !piece.isLocked && !piece.isSettling),
        isTrue,
      );
      expect(p.values.every((piece) => piece.priority == 0), isTrue);
    },
  );

  for (final grabbed in [0, 1]) {
    testWidgets(
      'grabbing member $grabbed moves both, raises both, and cancel releases both',
      (tester) async {
        final game = await boot(
          tester,
          InMemorySaveStore(),
          loose: {
            0: home(0) + offset,
            1: home(1) + offset,
            9: Vector2(1100, 550),
          },
        );
        final p = pieces(game);
        final before = {
          for (final e in p.entries) e.key: e.value.position.clone(),
        };
        final cameraBefore = game.camera.viewfinder.position.clone();
        final start = canvas(game, p[grabbed]!.position + p[grabbed]!.size / 2);
        final gesture = await tester.startGesture(start);
        await drag(tester, gesture, start, start + const Offset(60, -20));
        final delta = p[grabbed]!.position - before[grabbed]!;
        expect(delta.length, greaterThan(20));
        expect(
          (p[0]!.position - before[0]!).distanceTo(delta),
          lessThan(0.001),
        );
        expect(
          (p[1]!.position - before[1]!).distanceTo(delta),
          lessThan(0.001),
        );
        expectJoined(p[0]!, p[1]!);
        expect(p[0]!.priority, greaterThan(p[9]!.priority));
        expect(p[1]!.priority, greaterThan(p[9]!.priority));
        expect(p[9]!.position, before[9]);
        expect(game.camera.viewfinder.position, cameraBefore);
        await gesture.cancel();
        await tester.pump(const Duration(milliseconds: 16));
        expect(p[0]!.priority, 0);
        expect(p[1]!.priority, 0);
        expect(game.beginPieceDrag(p[1]!), isTrue);
        p[1]!.settle();
      },
    );
  }

  testWidgets('chunk-to-chunk merge moves all four on the next drag', (
    tester,
  ) async {
    final game = await boot(
      tester,
      InMemorySaveStore(),
      loose: {
        0: home(0) + offset,
        1: home(1) + offset,
        2: home(2) + offset + Vector2(120, 0),
        3: home(3) + offset + Vector2(120, 0),
      },
    );
    final p = pieces(game);
    game.movePieceTo(p[3]!, home(3) + offset + Vector2(20, 0));
    p[3]!.settle();
    await finishSettle(tester);
    game.beginPieceDrag(p[2]!);
    game.movePieceBy(p[2]!, Vector2(25, -20));
    for (final piece in p.values) {
      expect(
        piece.position.distanceTo(
          piece.correctPosition + offset + Vector2(25, -20),
        ),
        lessThan(0.001),
      );
    }
    p[2]!.settle();
  });

  testWidgets(
    'one member reaching home locks and saves the whole chunk atomically',
    (tester) async {
      final store = InMemorySaveStore();
      final sounds = _Sounds();
      final game = await boot(
        tester,
        store,
        sounds: sounds,
        loose: {0: home(0) + offset, 1: home(1) + offset},
      );
      final p = pieces(game);
      game.movePieceTo(p[1]!, home(1) + Vector2(30, 5));
      p[1]!.settle();
      game.persistProgress();
      await game.progressSaved;
      expect((await store.load(key))!.lockedPieceIndexes, isEmpty);
      expect(game.progress.lockedCount, 0);
      expect(
        p.values.every((piece) => !piece.containsLocalPoint(piece.size / 2)),
        isTrue,
      );
      await finishSettle(tester);
      await game.progressSaved;
      expect(game.progress.lockedCount, 2);
      expect(
        p.values.every(
          (piece) => piece.isLocked && piece.position == piece.correctPosition,
        ),
        isTrue,
      );
      expect((await store.load(key))!.lockedPieceIndexes.toSet(), {0, 1});
      expect(sounds.snaps, 1);
      expect(sounds.completes, 0);
    },
  );

  testWidgets('whole-chunk completion fires once and deletes the save', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final sounds = _Sounds();
    var completions = 0;
    final game = await boot(
      tester,
      store,
      columns: 2,
      rows: 1,
      sounds: sounds,
      onCompleted: () async {
        completions++;
        return true;
      },
      loose: {0: Vector2(400, 200), 1: Vector2(1200, 200)},
    );
    final p = pieces(game);
    game.movePieceTo(p[1]!, p[1]!.correctPosition + Vector2(20, 0));
    p[1]!.settle();
    await finishSettle(tester);
    expect(game.progress.isComplete, isTrue);
    expect(p.values.every((piece) => piece.isLocked), isTrue);
    expect(completions, 1);
    expect(sounds.snaps, 1);
    expect(sounds.completes, 1);
    expect(await store.exists(key), isFalse);
  });

  testWidgets('save during neighbor settle reloads as one draggable chunk', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    var game = await boot(
      tester,
      store,
      loose: {0: home(0) + offset, 1: home(1) + offset + Vector2(20, 5)},
    );
    pieces(game)[1]!.settle();
    await game.progressSaved;
    expect(pieces(game)[1]!.isSettling, isTrue);
    // Reopen before the old game's next animation frame.
    game = await boot(tester, store);
    final p = pieces(game);
    final before = p[0]!.position.clone();
    expect(game.beginPieceDrag(p[1]!), isTrue);
    game.movePieceBy(p[1]!, Vector2(50, -30));
    expect(
      p[0]!.position.distanceTo(before + Vector2(50, -30)),
      lessThan(0.001),
    );
    expectJoined(p[0]!, p[1]!);
    p[1]!.settle();
  });

  testWidgets(
    'tray lift joins a board neighbor while helper toggles stay independent',
    (tester) async {
      final game = await boot(
        tester,
        InMemorySaveStore(),
        loose: {1: home(1) + offset},
      );
      game.setEdgesOnlyFilter(true);
      game.setGhostPreview(true);
      await tester.pump(const Duration(milliseconds: 16));
      final visibleBefore = game.visibleTrayPieceIndexes.toSet();
      const start = Offset(50, 550);
      const lifted = Offset(50, 400);
      final gesture = await tester.startGesture(start);
      await drag(tester, gesture, start, lifted);
      final p = pieces(game);
      expect(p.keys.toSet(), {0, 1});
      await drag(
        tester,
        gesture,
        lifted,
        canvas(game, offset + Vector2(20, 0) + p[0]!.size / 2),
      );
      await gesture.up();
      await finishSettle(tester);
      expectJoined(p[0]!, p[1]!);
      expect(p[0]!.isLocked, isFalse);
      expect(game.visibleTrayPieceIndexes.toSet(), visibleBefore..remove(0));
      expect(game.ghostPreviewOpacity, 0.25);
      game.beginPieceDrag(p[1]!);
      game.movePieceBy(p[1]!, Vector2(20, 0));
      expectJoined(p[0]!, p[1]!);
      p[1]!.settle();
    },
  );

  testWidgets(
    'tray clearance translates a tall chunk without breaking its seam',
    (tester) async {
      final game = await boot(
        tester,
        InMemorySaveStore(),
        loose: {0: home(0) + offset, 6: home(6) + offset},
      );
      final p = pieces(game);
      game.movePieceTo(p[0]!, Vector2(400, 1100));
      p[0]!.settle();
      expectJoined(p[0]!, p[6]!);
      final bottom = canvas(game, p[6]!.position + Vector2(0, height)).dy;
      expect(bottom, lessThanOrEqualTo(484.001));
    },
  );

  testWidgets('a second member cannot claim an already held chunk', (
    tester,
  ) async {
    final game = await boot(
      tester,
      InMemorySaveStore(),
      loose: {0: home(0) + offset, 1: home(1) + offset},
    );
    final p = pieces(game);
    expect(game.beginPieceDrag(p[0]!), isTrue);
    expect(game.beginPieceDrag(p[1]!), isFalse);
    game.movePieceBy(p[0]!, Vector2(30, 0));
    p[0]!.settle();
    expect(game.beginPieceDrag(p[1]!), isTrue);
    p[1]!.settle();
  });

  testWidgets('120-piece restored chunk survives a gesture and save', (
    tester,
  ) async {
    final store = InMemorySaveStore();
    final game = await boot(
      tester,
      store,
      columns: 12,
      rows: 10,
      loose: {
        for (var i = 0; i < 120; i++)
          i: Vector2(i % 12 * (1600 / 12) + 200, i ~/ 12 * (1067 / 10) - 100),
      },
    );
    final p = pieces(game);
    final before = p[0]!.position.clone();
    final start = canvas(game, p[26]!.position + p[26]!.size / 2);
    final gesture = await tester.startGesture(start);
    await drag(tester, gesture, start, start + const Offset(30, -20));
    expect(p[0]!.position.distanceTo(before), greaterThan(20));
    expect(p.values.every((piece) => piece.priority == 100), isTrue);
    for (final piece in p.values) {
      expectJoined(p[0]!, piece);
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await game.progressSaved;
    final saved = (await store.load(key))!;
    expect(saved.isConsistentFor(120), isTrue);
    expect(saved.loosePiecePositions, hasLength(120));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
