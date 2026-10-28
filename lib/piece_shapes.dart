// Piece shape overview:
// 1. Every interior edge between two neighboring pieces gets a knob: a tab
//    (sticking out) on one piece and a matching blank (cut in) on the other.
//    Which side gets the tab is decided by a seeded random generator, so the
//    same seed always cuts the same puzzle — required for save & resume.
// 2. PieceShapeGrid holds those decisions and answers "what are the four
//    edge types of piece N?".
// 3. buildPiecePath turns one piece's four edge types into an outline Path
//    (in piece-local coordinates) that the renderer clips the image with.
//
// Geometry is pure and Flame-free so it can be unit-tested directly.

import 'dart:math';
import 'dart:ui';

/// One side of a piece: straight border, knob sticking out, or knob cut in.
enum EdgeType { flat, tab, blank }

/// The four edge types of a single piece, in piece-local terms.
class PieceShape {
  const PieceShape({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  final EdgeType top;
  final EdgeType right;
  final EdgeType bottom;
  final EdgeType left;
}

/// How far a tab sticks out past the piece rectangle, as a fraction of the
/// piece's shorter side. The renderer must leave at least this much margin
/// around each piece (head center depth + head radius, see below).
const knobOverhangFraction = _headCenterDepth + _headRadius;

// Knob proportions, as fractions of the piece's shorter side. The knob sits
// centered on its edge: a neck that pinches inward, then a circular head.
// The head (diameter 0.23) is wider than the neck, giving the classic
// jigsaw overhang that makes pieces look like they'd physically interlock.
const _neckBaseOffset = 0.10; // half-width of the neck where it meets the edge
const _neckControlOffset = 0.045; // quadratic control: pulls the waist inward
const _neckControlDepth = 0.047;
const _headEntryOffset = 0.0942; // where the neck meets the circular head
const _headEntryDepth = 0.094;
const _headRadius = 0.115;
const _headCenterDepth = 0.16;

/// Deterministic per-edge knob directions for one puzzle.
///
/// Guarantees: border edges are flat, and the two pieces sharing an interior
/// edge always get complementary types (one tab, one blank).
class PieceShapeGrid {
  PieceShapeGrid.generate({
    required this.columns,
    required this.rows,
    required int seed,
  }) {
    final random = _Xorshift32(seed);
    _horizontalTabPointsDown = List.generate(
      (rows - 1) * columns,
      (_) => random.nextBool(),
    );
    _verticalTabPointsRight = List.generate(
      rows * (columns - 1),
      (_) => random.nextBool(),
    );
  }

  final int columns;
  final int rows;

  // One flag per interior edge. "Points down/right" means the knob bulges
  // toward the lower/right piece, i.e. the upper/left piece owns the tab.
  late final List<bool> _horizontalTabPointsDown;
  late final List<bool> _verticalTabPointsRight;

  /// Knob direction of the horizontal edge below (row, column).
  bool _tabPointsDown(int row, int column) =>
      _horizontalTabPointsDown[row * columns + column];

  /// Knob direction of the vertical edge right of (row, column).
  bool _tabPointsRight(int row, int column) =>
      _verticalTabPointsRight[row * (columns - 1) + column];

  PieceShape shapeAt(int row, int column) {
    return PieceShape(
      top: row == 0
          ? EdgeType.flat
          : (_tabPointsDown(row - 1, column) ? EdgeType.blank : EdgeType.tab),
      bottom: row == rows - 1
          ? EdgeType.flat
          : (_tabPointsDown(row, column) ? EdgeType.tab : EdgeType.blank),
      left: column == 0
          ? EdgeType.flat
          : (_tabPointsRight(row, column - 1) ? EdgeType.blank : EdgeType.tab),
      right: column == columns - 1
          ? EdgeType.flat
          : (_tabPointsRight(row, column) ? EdgeType.tab : EdgeType.blank),
    );
  }

  PieceShape shapeAtIndex(int index) =>
      shapeAt(index ~/ columns, index % columns);
}

/// Stable 32-bit FNV-1a hash of a puzzle key, used as the shape seed.
/// String.hashCode is not guaranteed stable across Dart versions or
/// platforms, and a resumed puzzle must be re-cut exactly the same way.
int shapeSeedForKey(String key) {
  var hash = 0x811C9DC5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    // Split the FNV prime so each product stays exact in JavaScript numbers.
    // Only the lowest byte contributes to the product with 0x01000000.
    final lowProduct = hash * 0x0193;
    final highProduct = (hash & 0xFF) << 24;
    hash = (lowProduct + highProduct) & 0xFFFFFFFF;
  }
  return hash;
}

/// The outline of one piece whose base rectangle is (0,0)..(width,height).
/// Tabs extend outside that rectangle by up to [knobOverhangFraction] of the
/// shorter side; blanks cut into it by the same amount.
Path buildPiecePath({
  required PieceShape shape,
  required double width,
  required double height,
}) {
  final knobScale = min(width, height);
  final path = Path()..moveTo(0, 0);

  // Each edge is drawn walking clockwise around the piece. The map function
  // converts edge-local coordinates (d = distance along the edge from its
  // start, v = outward distance) into piece coordinates.
  _addEdge(
    path,
    shape.top,
    length: width,
    knobScale: knobScale,
    map: (d, v) => Offset(d, -v),
  );
  _addEdge(
    path,
    shape.right,
    length: height,
    knobScale: knobScale,
    map: (d, v) => Offset(width + v, d),
  );
  _addEdge(
    path,
    shape.bottom,
    length: width,
    knobScale: knobScale,
    map: (d, v) => Offset(width - d, height + v),
  );
  _addEdge(
    path,
    shape.left,
    length: height,
    knobScale: knobScale,
    map: (d, v) => Offset(-v, height - d),
  );
  return path..close();
}

void _addEdge(
  Path path,
  EdgeType type, {
  required double length,
  required double knobScale,
  required Offset Function(double d, double v) map,
}) {
  final end = map(length, 0);
  if (type == EdgeType.flat) {
    path.lineTo(end.dx, end.dy);
    return;
  }

  // Blanks are tabs mirrored into the piece: flip the outward axis.
  final direction = type == EdgeType.tab ? 1.0 : -1.0;
  final mid = length / 2;
  final s = knobScale;
  Offset knobPoint(double offsetFromMid, double depth) =>
      map(mid + offsetFromMid * s, direction * depth * s);

  final neckStart = knobPoint(-_neckBaseOffset, 0);
  final neckStartControl = knobPoint(-_neckControlOffset, _neckControlDepth);
  final headEntry = knobPoint(-_headEntryOffset, _headEntryDepth);
  final headExit = knobPoint(_headEntryOffset, _headEntryDepth);
  final neckEndControl = knobPoint(_neckControlOffset, _neckControlDepth);
  final neckEnd = knobPoint(_neckBaseOffset, 0);

  path
    ..lineTo(neckStart.dx, neckStart.dy)
    ..quadraticBezierTo(
      neckStartControl.dx,
      neckStartControl.dy,
      headEntry.dx,
      headEntry.dy,
    )
    // The long way around the circular head, over its apex. All four edge
    // maps mirror orientation the same way, so one clockwise rule works for
    // every side; mirroring a blank flips it.
    ..arcToPoint(
      headExit,
      radius: Radius.circular(_headRadius * s),
      largeArc: true,
      clockwise: type == EdgeType.tab,
    )
    ..quadraticBezierTo(
      neckEndControl.dx,
      neckEndControl.dy,
      neckEnd.dx,
      neckEnd.dy,
    )
    ..lineTo(end.dx, end.dy);
}

/// Tiny xorshift32 generator. Used instead of dart:math's Random because its
/// seeded sequence is not specified to match across platforms, and a puzzle
/// cut on one device may be resumed after an engine update on another.
class _Xorshift32 {
  _Xorshift32(int seed)
    // Xorshift must not start at 0 (it would stay 0 forever).
    : _state = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;

  int _state;

  bool nextBool() {
    var x = _state;
    x = (x ^ (x << 13)) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x = (x ^ (x << 5)) & 0xFFFFFFFF;
    _state = x;
    return x.isOdd;
  }
}
