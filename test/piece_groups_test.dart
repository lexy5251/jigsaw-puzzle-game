import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/piece_groups.dart';

void main() {
  PieceGroups board({int columns = 4, int rows = 3}) =>
      PieceGroups(columns: columns, rows: rows, cellWidth: 100, cellHeight: 80);

  GroupDrop drop(
    PieceGroups groups,
    int piece, {
    Set<int> unavailable = const {},
  }) => groups.drop(piece, boardTolerance: 40, unavailable: unavailable);

  void addAtOffset(PieceGroups groups, int piece, Point<double> offset) =>
      groups.add(piece, groups.correctPosition(piece) + offset);

  for (final neighbor in [1, 4, 6, 9]) {
    test('joins picture-neighbor $neighbor on the correct side of 5', () {
      final groups = board();
      addAtOffset(groups, neighbor, const Point(300.0, 200.0));
      addAtOffset(groups, 5, const Point(313.0, 205.0));
      final result = drop(groups, 5);
      expect(result.joined, isTrue);
      expect(result.locked, isFalse);
      expect(result.members, {5, neighbor});
      expect(groups.positionOf(5), const Point(400.0, 280.0));
      expect(
        groups.positionOf(5) - groups.positionOf(neighbor),
        groups.correctPosition(5) - groups.correctPosition(neighbor),
      );
    });
  }

  test('a removed piece leaves others alone and can be added again', () {
    final groups = board();
    addAtOffset(groups, 0, const Point(300.0, 200.0));
    addAtOffset(groups, 5, const Point(500.0, 100.0));

    groups.remove(0); // Returned to the tray.
    expect(
      groups.positionOf(5),
      groups.correctPosition(5) + const Point(500.0, 100.0),
    );

    // Lifting it out of the tray again re-registers the same index.
    groups.add(0, const Point(10.0, 20.0));
    expect(groups.membersOf(0), {0});
    expect(groups.positionOf(0), const Point(10.0, 20.0));
  });

  test('rejects a correct neighbor on the wrong side', () {
    final groups = board();
    groups.add(0, const Point(500.0, 200.0));
    groups.add(1, const Point(400.0, 200.0));
    expect(drop(groups, 1).joined, isFalse);
  });

  for (final pair in [(0, 2), (0, 5), (3, 4)]) {
    test('rejects non-neighbors ${pair.$1}/${pair.$2}, including row wrap', () {
      final groups = board();
      addAtOffset(groups, pair.$1, const Point(300.0, 200.0));
      addAtOffset(groups, pair.$2, const Point(300.0, 200.0));
      expect(drop(groups, pair.$1).joined, isFalse);
    });
  }

  for (final error in [
    const Point(24.0, 0.0),
    const Point(0.0, 24.01),
    const Point(18.0, 18.0),
  ]) {
    test('rejects offset error $error outside radial 30% tolerance', () {
      final groups = board();
      addAtOffset(groups, 0, const Point(300.0, 200.0));
      addAtOffset(groups, 1, const Point(300.0, 200.0) + error);
      expect(drop(groups, 1).joined, isFalse);
    });
  }

  test('dragging any member preserves every exact relative offset', () {
    final groups = board();
    for (final i in [0, 1, 4]) {
      addAtOffset(groups, i, const Point(300.0, 200.0));
    }
    drop(groups, 0);
    for (final grabbed in [0, 1, 4]) {
      final before = {
        for (final i in [0, 1, 4]) i: groups.positionOf(i),
      };
      groups.translate(grabbed, const Point(12.5, -7.25));
      for (final i in before.keys) {
        expect(groups.positionOf(i), before[i]! + const Point(12.5, -7.25));
      }
    }
    groups.moveTo(4, const Point(500.0, 480.0));
    expect(groups.positionOf(0), const Point(500.0, 400.0));
    expect(groups.positionOf(1), const Point(600.0, 400.0));
  });

  test('merges chunk with chunk, preserving the stationary chunk position', () {
    final groups = board();
    groups.restore(
      positions: {
        0: const Point(300.0, 200.0),
        1: const Point(400.0, 200.0),
        2: const Point(515.0, 205.0),
        3: const Point(615.0, 205.0),
      },
    );
    expect(groups.membersOf(0), {0, 1});
    expect(groups.membersOf(2), {2, 3});
    expect(drop(groups, 3).members, {0, 1, 2, 3});
    expect(groups.positionOf(0), const Point(300.0, 200.0));
    expect(groups.positionOf(3), const Point(600.0, 200.0));
  });

  test('chooses nearest alignment without pulling a competing near chunk', () {
    final groups = board();
    addAtOffset(groups, 0, const Point(300.0, 200.0));
    addAtOffset(groups, 1, const Point(310.0, 200.0));
    addAtOffset(groups, 2, const Point(330.0, 200.0));
    expect(drop(groups, 1).members, {0, 1});
    expect(groups.membersOf(2), {2});
    expect(groups.positionOf(2), const Point(530.0, 200.0));
  });

  test('equal-distance choices are independent of insertion order', () {
    for (final order in [
      [0, 1, 2],
      [2, 1, 0],
    ]) {
      final groups = board();
      for (final i in order) {
        addAtOffset(groups, i, Point(300.0 + i * 10, 200.0));
      }
      expect(drop(groups, 1).members, {0, 1});
    }
  });

  test('another pointer or settling member excludes its entire chunk', () {
    final groups = board();
    groups.restore(
      positions: {
        0: const Point(300.0, 200.0),
        1: const Point(400.0, 200.0),
        2: const Point(510.0, 200.0),
      },
    );
    expect(drop(groups, 2, unavailable: {0}).joined, isFalse);
    expect(drop(groups, 2).members, {0, 1, 2});
  });

  test('any member landing near home locks the entire chunk', () {
    final groups = board();
    groups.restore(
      positions: {
        0: const Point(300.0, 200.0),
        1: const Point(400.0, 200.0),
        4: const Point(300.0, 280.0),
      },
    );
    groups.moveTo(4, const Point(30.0, 85.0));
    final result = drop(groups, 4);
    expect(result.locked, isTrue);
    expect(result.members, {0, 1, 4});
    for (final i in result.members) {
      expect(groups.isLocked(i), isTrue);
      expect(groups.positionOf(i), groups.correctPosition(i));
    }
    groups.translate(1, const Point(100.0, 100.0));
    expect(groups.positionOf(0), groups.correctPosition(0));
  });

  test('board tolerance is unchanged; joining can bring a chunk within it', () {
    final groups = board();
    addAtOffset(groups, 0, const Point(39.0, 0.0));
    addAtOffset(groups, 1, const Point(55.0, 0.0));
    final result = drop(groups, 1);
    expect(result.joined, isTrue);
    expect(result.locked, isTrue);
    expect(groups.positionOf(0), groups.correctPosition(0));
  });

  test('JSON save/load rebuilds fractional chunks with roundoff only', () {
    final groups = PieceGroups(
      columns: 12,
      rows: 10,
      cellWidth: 1000 / 12,
      cellHeight: 777 / 10,
    );
    for (final i in [0, 1, 12, 13]) {
      addAtOffset(groups, i, const Point(301.23456789, -123.456789));
    }
    drop(groups, 0);
    for (var i = 0; i < 1000; i++) {
      groups.translate(13, const Point(0.1, -0.2));
    }
    final json = jsonDecode(
      jsonEncode({
        for (final i in [0, 1, 12, 13])
          '$i': [groups.positionOf(i).x, groups.positionOf(i).y],
      }),
    ) as Map<String, dynamic>;
    final restored = PieceGroups(
      columns: 12,
      rows: 10,
      cellWidth: 1000 / 12,
      cellHeight: 777 / 10,
    );
    restored.restore(
      positions: {
        for (final e in json.entries)
          int.parse(e.key): Point(
            (e.value[0] as num).toDouble(),
            (e.value[1] as num).toDouble(),
          ),
        // A nearly aligned old loose piece must stay separate.
        2: groups.positionOf(1) + Point(1000 / 12 + 0.001, 0.0),
      },
    );
    expect(restored.membersOf(13), {0, 1, 12, 13});
    expect(restored.membersOf(2), {2});
  });

  test('restore propagates an existing board lock through exact neighbors', () {
    final groups = board();
    groups.restore(
      positions: {
        0: const Point(0.0, 0.0),
        1: const Point(100.0, 0.0),
        4: const Point(0.0, 80.0),
        5: const Point(101.0, 80.0),
      },
      lockedPieces: [0],
    );
    expect(groups.membersOf(1), {0, 1, 4});
    expect(groups.isLocked(4), isTrue);
    expect(groups.isLocked(5), isFalse);
  });

  test('Float32 roundoff rebuilds fractional chunks without joining nearby loose pieces', () {
    final groups = PieceGroups(
      columns: 12,
      rows: 10,
      cellWidth: 1600 / 12,
      cellHeight: 1067 / 10,
    );
    Point<double> stored(Point<double> p) {
      final values = Float32List.fromList([p.x, p.y]);
      return Point(values[0], values[1]);
    }

    final positions = {
      for (var i = 0; i < 118; i++)
        i: stored(
          groups.correctPosition(i) + const Point(301.23456789, -123.456789),
        ),
      118: stored(
        groups.correctPosition(118) + const Point(301.24456789, -123.456789),
      ),
      119: const Point(1e10, 1e10),
    };
    groups.restore(
      positions: positions,
      relativePositionRoundoff: 2 * 1.1920928955078125e-7,
    );
    expect(groups.membersOf(0), hasLength(118));
    expect(groups.membersOf(118), {118});
    expect(groups.membersOf(119), {119});
  });

  test('120-piece drag and drop math fits comfortably in a frame budget', () {
    final groups = board(columns: 12, rows: 10);
    groups.restore(
      positions: {
        for (var i = 0; i < 120; i++)
          i: groups.correctPosition(i) + const Point(300.0, 200.0),
      },
    );
    expect(groups.membersOf(119), hasLength(120));
    final watch = Stopwatch()..start();
    for (var frame = 0; frame < 1200; frame++) {
      groups.translate(frame % 120, const Point(0.125, -0.0625));
      for (var i = 0; i < 120; i++) {
        groups.positionOf(i);
      }
      drop(groups, frame % 120);
    }
    watch.stop();
    // 1200 frames at 60Hz allow 20s; this guards a much smaller math budget
    // without pretending that a unit test measures device rendering speed.
    expect(watch.elapsedMilliseconds, lessThan(2000));
    expect(groups.membersOf(0), hasLength(120));
    expect(
      groups.positionOf(119) - groups.positionOf(0),
      groups.correctPosition(119),
    );
  });
}
