import 'dart:collection';
import 'dart:math';

/// Rigid chunks of picture-neighbors. Coordinates are base-cell top-lefts;
/// this model has no dependency on Flame, Flutter, sprites, or save formats.
/// Every member shares one translation from its solved position, so dragging
/// cannot accumulate different rounding errors in different members.
class PieceGroups {
  PieceGroups({
    required this.columns,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
  }) : assert(columns > 0 && rows > 0),
       assert(cellWidth > 0 && cellHeight > 0);

  final int columns;
  final int rows;
  final double cellWidth;
  final double cellHeight;
  final Map<int, _Group> _groups = {};

  static const neighborToleranceFraction = 0.3;

  // Only accommodates arithmetic/JSON roundoff, not a second snap tolerance.
  double get _roundoff => min(cellWidth, cellHeight) * 1e-9;

  Point<double> correctPosition(int index) =>
      Point((index % columns) * cellWidth, (index ~/ columns) * cellHeight);

  Point<double> positionOf(int index) =>
      correctPosition(index) + _groups[index]!.offset;

  Set<int> membersOf(int index) => UnmodifiableSetView(_groups[index]!.members);

  bool isLocked(int index) => _groups[index]!.locked;

  void add(int index, Point<double> position, {bool locked = false}) {
    assert(index >= 0 && index < columns * rows);
    assert(!_groups.containsKey(index));
    _groups[index] = _Group(
      {index},
      locked ? const Point(0.0, 0.0) : position - correctPosition(index),
      locked,
    );
  }

  /// Removes a lone, unlocked piece — e.g. one returned to the tray, which
  /// holds single pieces only. The index can be re-added later.
  void remove(int index) {
    final group = _groups[index]!;
    assert(!group.locked && group.members.length == 1);
    _groups.remove(index);
  }

  /// Reconstructs connectivity from exact relative offsets in existing saves.
  /// Sorting makes the result independent of JSON/map insertion order.
  /// [relativePositionRoundoff] accommodates a caller's coordinate storage
  /// precision (e.g. Float32); it is not the gameplay join tolerance.
  void restore({
    required Map<int, Point<double>> positions,
    Iterable<int> lockedPieces = const [],
    double relativePositionRoundoff = 0,
  }) {
    _groups.clear();
    final locked = lockedPieces.toSet();
    final indexes = positions.keys.toList()..sort();
    for (final index in indexes) {
      add(index, positions[index]!, locked: locked.contains(index));
    }
    for (final index in indexes) {
      for (final neighbor in _neighbors(index)) {
        final target = _groups[neighbor];
        final source = _groups[index]!;
        if (target != null &&
            !identical(source, target) &&
            _aligned(
              source,
              target,
              relativeRoundoff: relativePositionRoundoff,
            )) {
          _merge(target, source);
        }
      }
    }
  }

  /// Grabbing any member moves the entire group by the same translation.
  void moveTo(int index, Point<double> position) {
    final group = _groups[index]!;
    if (!group.locked) group.offset = position - correctPosition(index);
  }

  void translate(int index, Point<double> delta) {
    final group = _groups[index]!;
    if (!group.locked) group.offset += delta;
  }

  /// Resolves one release. Board snapping keeps its existing tolerance and
  /// takes precedence. Otherwise choose the closest eligible picture-neighbor
  /// (stable index tie-break), align exactly, then absorb exact contacts only.
  /// Groups held by another pointer or still settling are unavailable.
  GroupDrop drop(
    int index, {
    required double boardTolerance,
    Set<int> unavailable = const {},
  }) {
    var group = _groups[index]!;
    if (group.locked) {
      return GroupDrop(membersOf(index), joined: false, locked: true);
    }
    var joined = false;
    if (!_nearBoard(group, boardTolerance)) {
      final blocked = {
        for (final piece in unavailable)
          if (_groups.containsKey(piece)) _groups[piece]!,
      };
      final tolerance = min(cellWidth, cellHeight) * neighborToleranceFraction;
      var bestDistance = tolerance * tolerance;
      int? bestSource;
      int? bestNeighbor;
      for (final member in group.members) {
        for (final neighbor in _neighbors(member)) {
          final target = _groups[neighbor];
          if (target == null ||
              identical(group, target) ||
              blocked.contains(target)) {
            continue;
          }
          final distance = _distanceSquared(group.offset, target.offset);
          if (distance < bestDistance ||
              (bestNeighbor != null &&
                  distance == bestDistance &&
                  (member < bestSource! ||
                      (member == bestSource && neighbor < bestNeighbor)))) {
            bestDistance = distance;
            bestSource = member;
            bestNeighbor = neighbor;
          }
        }
      }
      if (bestNeighbor != null) {
        group = _merge(group, _groups[bestNeighbor]!);
        joined = true;

        // One drop can close several seams. Walk the new perimeter without
        // pulling other chunks that are merely near a different alignment.
        final queue = group.members.toList();
        for (var i = 0; i < queue.length; i++) {
          for (final neighbor in _neighbors(queue[i])) {
            final target = _groups[neighbor];
            if (target != null &&
                !identical(group, target) &&
                !blocked.contains(target) &&
                _aligned(group, target)) {
              queue.addAll(target.members);
              group = _merge(target, group);
            }
          }
        }
      }
    }
    if (_nearBoard(group, boardTolerance) || group.locked) {
      group
        ..offset = const Point(0.0, 0.0)
        ..locked = true;
    }
    return GroupDrop(membersOf(index), joined: joined, locked: group.locked);
  }

  bool _nearBoard(_Group group, double tolerance) =>
      _distanceSquared(group.offset, const Point(0.0, 0.0)) <
      tolerance * tolerance;

  bool _aligned(_Group a, _Group b, {double relativeRoundoff = 0}) {
    // Bound the rounding error for this pair only. A far-away unrelated piece
    // must not increase the restoration tolerance for the rest of the board.
    final offsetScale = max(
      max(a.offset.x.abs(), a.offset.y.abs()),
      max(b.offset.x.abs(), b.offset.y.abs()),
    );
    final scale = max(columns * cellWidth, rows * cellHeight) + offsetScale;
    final tolerance = max(_roundoff, scale * relativeRoundoff);
    return _distanceSquared(a.offset, b.offset) <= tolerance * tolerance;
  }

  // There are at most four candidates per member; no all-pairs board scan.
  Iterable<int> _neighbors(int index) sync* {
    final column = index % columns;
    if (index >= columns) yield index - columns;
    if (column > 0) yield index - 1;
    if (column < columns - 1) yield index + 1;
    if (index < columns * (rows - 1)) yield index + columns;
  }

  /// Keeps the target's exact translation, unless either group is anchored.
  _Group _merge(_Group source, _Group target) {
    if (source.locked || target.locked) {
      target
        ..offset = const Point(0.0, 0.0)
        ..locked = true;
    }
    for (final member in source.members) {
      target.members.add(member);
      _groups[member] = target;
    }
    return target;
  }

  static double _distanceSquared(Point<double> a, Point<double> b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy;
  }
}

class _Group {
  _Group(this.members, this.offset, this.locked);

  final Set<int> members;
  Point<double> offset;
  bool locked;
}

class GroupDrop {
  GroupDrop(Set<int> members, {required this.joined, required this.locked})
    : members = Set.unmodifiable(members);

  final Set<int> members;
  final bool joined;
  final bool locked;
}
