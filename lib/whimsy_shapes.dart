// Whimsy pieces overview:
// 1. A whimsy piece is one interior cell cut as a recognizable figure (heart,
//    star, fish, ...) instead of a knobbed square. The figure is centered on
//    the cell and sized per shape ([whimsyFigureSpans]) so it reads about as
//    big as a knobbed piece: its extreme tips cross the cell edge and bite
//    into the orthogonal neighbors, exactly like a tab does.
// 2. The photo around the figure is split between the four orthogonal
//    neighbors: each absorbs one triangle of the whimsy cell (cell corners
//    to cell center) and gives up whatever the figure covers — inside the
//    whimsy cell and, where a tip crosses the shared edge, inside its own
//    cell. The five pieces tile the figure's plus-shaped reach exactly, so
//    every photo pixel belongs to exactly one piece — no gaps, no double
//    cover. Figures never reach the diagonal neighbors — the builder clips
//    them to the plus region (and tests pin it on square cells), so the
//    diagonals keep their plain knobbed outlines.
// 3. Figures are authored once in a unit box (0,0)..(1,1), normalized by
//    their true contour bounds and scaled per cell. Every figure is a single
//    closed contour with no enclosed holes: a hole would strand photo pixels
//    no neighbor could reach.
//
// Geometry is pure and Flame-free so it can be unit-tested directly.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

/// The figure library. `.name` is the stable identifier if whimsies ever
/// need to be referenced outside geometry (analytics, completion copy).
enum WhimsyShape {
  heart,
  star,
  fish,
  sailboat,
  cat,
  teacup,
  butterfly,
  flower,
  leaf,
  bird,
  moon,
  snowflake,
}

/// Figure size per shape: tip-to-tip span of the figure's longer axis as a
/// fraction of the cell's shorter side (1.0 = exactly one cell). The
/// owner-tunable knob. Solid figures (heart, moon) carry more visual mass
/// than lacy ones (star, snowflake) at the same span, so lacy shapes get
/// more — the goal is every figure reading about as big as a knobbed piece.
///
/// Two rules bound the values (both tested per shape):
/// - On each axis the figure must either cross the cell edge by at least
///   [whimsyAxisCrossMin] or stay inside [whimsyAxisInsideMax]: an extreme
///   stopping just short of the edge would pinch the neighbor's photo into
///   a hair-thin thread along the seam.
/// - Every protrusion must stay under the knob overhang, so whimsy sprites
///   keep the plain knob bleed, and well clear of the cell corners, so no
///   figure ever reaches a diagonal neighbor.
const whimsyFigureSpans = <WhimsyShape, double>{
  WhimsyShape.heart: 1.10,
  WhimsyShape.star: 1.18,
  WhimsyShape.fish: 1.06,
  WhimsyShape.sailboat: 1.08,
  WhimsyShape.cat: 1.06,
  WhimsyShape.teacup: 1.06,
  WhimsyShape.butterfly: 1.09,
  WhimsyShape.flower: 1.12,
  WhimsyShape.leaf: 1.12,
  WhimsyShape.bird: 1.06,
  WhimsyShape.moon: 1.04,
  WhimsyShape.snowflake: 1.18,
};

/// Per-axis extent limits for [whimsyFigureSpans], as fractions of the
/// cell's shorter side: stay at least this far inside the cell...
const whimsyAxisInsideMax = 0.92;

/// ...or cross the seam by at least this much.
const whimsyAxisCrossMin = 1.005;

/// Where a neighbor piece sits relative to the whimsy cell. Also names the
/// triangle of the whimsy cell that neighbor absorbs (the one touching
/// their shared edge).
enum WhimsySide { above, below, leftOf, rightOf }

/// True contour bounds of each unit figure, measured once by walking the
/// path. Path.getBounds() includes curve control points and can over-report
/// by a few percent, which would silently under-scale curvy figures and
/// could park an extreme in the forbidden near-seam band (see
/// [whimsyAxisInsideMax]) — so the real extremes are sampled and cached.
final _tightUnitBounds = <WhimsyShape, Rect>{};

Rect whimsyUnitBounds(WhimsyShape shape) =>
    _tightUnitBounds.putIfAbsent(shape, () {
      // computeMetrics flattens curves to a fixed absolute tolerance — far
      // too coarse on a unit-sized path — so measure a 1000x copy.
      const measureScale = 1000.0;
      final measured = _unitFigure(shape).transform(
        Float64List.fromList([
          measureScale, 0, 0, 0, //
          0, measureScale, 0, 0, //
          0, 0, 1, 0, //
          0, 0, 0, 1,
        ]),
      );
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final metric in measured.computeMetrics()) {
        // ~2-of-1000 arc-length steps: deviation between samples is far
        // below the 0.005-of-cell tolerance anything downstream cares about.
        final steps = max(64, (metric.length / 2).ceil());
        for (var i = 0; i <= steps; i++) {
          final position = metric
              .getTangentForOffset(metric.length * i / steps)!
              .position;
          minX = min(minX, position.dx);
          minY = min(minY, position.dy);
          maxX = max(maxX, position.dx);
          maxY = max(maxY, position.dy);
        }
      }
      return Rect.fromLTRB(
        minX / measureScale,
        minY / measureScale,
        maxX / measureScale,
        maxY / measureScale,
      );
    });

/// The figure outline for a whimsy cell, in cell-local coordinates
/// (0,0)..(cellWidth,cellHeight), centered, scaled uniformly so a heart
/// stays a heart on non-square cells.
Path buildWhimsyFigurePath({
  required WhimsyShape shape,
  required double cellWidth,
  required double cellHeight,
}) {
  final tight = whimsyUnitBounds(shape);
  final scale =
      whimsyFigureSpans[shape]! *
      min(cellWidth, cellHeight) /
      max(tight.width, tight.height);
  // Column-major 4x4: scale by the span, then land the figure's true center
  // on the cell center.
  final transform = Float64List.fromList([
    scale, 0, 0, 0, //
    0, scale, 0, 0, //
    0, 0, 1, 0, //
    cellWidth / 2 - tight.center.dx * scale,
    cellHeight / 2 - tight.center.dy * scale, 0, 1,
  ]);
  final figure = _unitFigure(shape).transform(transform);
  // Only the four flap neighbors subtract this path from their outlines;
  // a diagonal neighbor's plain knobbed cut knows nothing about it, so any
  // ink past a cell corner would double-paint over that piece. Clipping to
  // the cell-plus-flaps region makes "never reaches a diagonal neighbor"
  // true by construction — on square cells the leaf's diagonal tips land
  // exactly there, truncated here by a few percent instead of overlapping.
  final plus = Path()
    ..addRect(Rect.fromLTRB(-cellWidth, 0, 2 * cellWidth, cellHeight))
    ..addRect(Rect.fromLTRB(0, -cellHeight, cellWidth, 2 * cellHeight));
  return Path.combine(PathOperation.intersect, figure, plus);
}

/// A neighbor's outline when it borders a whimsy cell: its normal outline
/// (the facing edge must be flat), plus its triangle of the whimsy cell,
/// minus the figure. Composed once at cut time — the result is a plain
/// Path, so per-frame rendering pays nothing extra.
Path buildWhimsyNeighborOutline({
  required Path basePath,
  required WhimsySide side,
  required Path figurePath,
  required double cellWidth,
  required double cellHeight,
}) {
  // Whimsy-cell origin expressed in the neighbor's local coordinates.
  final whimsyOrigin = switch (side) {
    WhimsySide.above => Offset(0, cellHeight),
    WhimsySide.below => Offset(0, -cellHeight),
    WhimsySide.leftOf => Offset(cellWidth, 0),
    WhimsySide.rightOf => Offset(-cellWidth, 0),
  };
  final flap = _flapTriangle(
    side,
    cellWidth,
    cellHeight,
  ).shift(whimsyOrigin);
  final withFlap = Path.combine(PathOperation.union, basePath, flap);
  return Path.combine(
    PathOperation.difference,
    withFlap,
    figurePath.shift(whimsyOrigin),
  );
}

/// The triangle of the whimsy cell absorbed by the neighbor on [side], in
/// whimsy-cell coordinates: the shared edge plus the cell center. The four
/// triangles tile the cell exactly.
Path _flapTriangle(WhimsySide side, double w, double h) {
  final center = Offset(w / 2, h / 2);
  final (a, b) = switch (side) {
    WhimsySide.above => (Offset.zero, Offset(w, 0)),
    WhimsySide.below => (Offset(0, h), Offset(w, h)),
    WhimsySide.leftOf => (Offset.zero, Offset(0, h)),
    WhimsySide.rightOf => (Offset(w, 0), Offset(w, h)),
  };
  return Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(center.dx, center.dy)
    ..close();
}

/// Unit-box (0,0)..(1,1) silhouettes. Hand-authored: each is a single
/// closed contour, chunky enough to read at a 15x15 board's ~60px figure.
Path _unitFigure(WhimsyShape shape) => switch (shape) {
  WhimsyShape.heart => _heart(),
  WhimsyShape.star => _star(),
  WhimsyShape.fish => _fish(),
  WhimsyShape.sailboat => _sailboat(),
  WhimsyShape.cat => _cat(),
  WhimsyShape.teacup => _teacup(),
  WhimsyShape.butterfly => _butterfly(),
  WhimsyShape.flower => _flower(),
  WhimsyShape.leaf => _leaf(),
  WhimsyShape.bird => _bird(),
  WhimsyShape.moon => _moon(),
  WhimsyShape.snowflake => _snowflake(),
};

Path _heart() => Path()
  ..moveTo(0.5, 0.92)
  ..cubicTo(0.26, 0.70, 0.05, 0.52, 0.05, 0.31)
  ..cubicTo(0.05, 0.14, 0.19, 0.06, 0.31, 0.08)
  ..cubicTo(0.40, 0.10, 0.47, 0.17, 0.5, 0.26)
  ..cubicTo(0.53, 0.17, 0.60, 0.10, 0.69, 0.08)
  ..cubicTo(0.81, 0.06, 0.95, 0.14, 0.95, 0.31)
  ..cubicTo(0.95, 0.52, 0.74, 0.70, 0.5, 0.92)
  ..close();

Path _star() {
  // Five points; the inner radius is fatter than a true pentagram so the
  // notches don't become photo slivers on small cells.
  const outer = 0.5, inner = 0.21;
  final path = Path();
  for (var k = 0; k < 5; k++) {
    final tip = -pi / 2 + k * 2 * pi / 5;
    final valley = tip + pi / 5;
    final t = Offset(0.5 + outer * cos(tip), 0.5 + outer * sin(tip));
    final v = Offset(0.5 + inner * cos(valley), 0.5 + inner * sin(valley));
    if (k == 0) {
      path.moveTo(t.dx, t.dy);
    } else {
      path.lineTo(t.dx, t.dy);
    }
    path.lineTo(v.dx, v.dy);
  }
  return path..close();
}

Path _fish() => Path()
  ..moveTo(0.05, 0.50) // nose
  ..cubicTo(0.18, 0.22, 0.46, 0.16, 0.62, 0.34) // back
  ..cubicTo(0.66, 0.38, 0.68, 0.42, 0.70, 0.46) // taper to tail joint
  ..lineTo(0.93, 0.24) // upper tail tip
  ..cubicTo(0.89, 0.40, 0.89, 0.60, 0.93, 0.76) // tail trailing edge
  ..lineTo(0.70, 0.54)
  ..cubicTo(0.68, 0.58, 0.66, 0.62, 0.62, 0.66)
  ..cubicTo(0.46, 0.84, 0.18, 0.78, 0.05, 0.50) // belly
  ..close();

Path _sailboat() => Path()
  // A right-triangle sail (vertical mast edge) over a wide hull with long
  // deck ledges on both sides — the ledges are what keep it from reading
  // as a plain triangle.
  ..moveTo(0.02, 0.68) // bow
  ..lineTo(0.24, 0.68)
  ..quadraticBezierTo(0.36, 0.32, 0.68, 0.04) // billowing leading edge
  ..lineTo(0.68, 0.68) // mast edge back to the deck
  ..lineTo(0.98, 0.68) // stern ledge
  ..lineTo(0.86, 0.94)
  ..lineTo(0.14, 0.94)
  ..close();

Path _cat() => Path()
  ..moveTo(0.33, 0.34) // left cheek below the ear
  ..lineTo(0.30, 0.10) // left ear tip
  ..lineTo(0.44, 0.20)
  ..cubicTo(0.48, 0.18, 0.56, 0.18, 0.60, 0.20) // top of head between ears
  ..lineTo(0.74, 0.10) // right ear tip
  ..lineTo(0.71, 0.34)
  ..cubicTo(0.76, 0.42, 0.76, 0.46, 0.72, 0.52) // jaw into neck
  ..cubicTo(0.82, 0.62, 0.86, 0.70, 0.86, 0.80) // seated body, right side
  ..cubicTo(0.92, 0.78, 0.97, 0.81, 0.97, 0.87) // tail against the flank
  ..quadraticBezierTo(0.96, 0.92, 0.88, 0.92)
  ..lineTo(0.22, 0.92) // base
  ..quadraticBezierTo(0.14, 0.92, 0.14, 0.86)
  ..cubicTo(0.14, 0.74, 0.20, 0.62, 0.32, 0.52) // body back up to the neck
  ..cubicTo(0.28, 0.46, 0.28, 0.42, 0.33, 0.34)
  ..close();

Path _teacup() => Path()
  ..moveTo(0.14, 0.24) // rim left
  ..lineTo(0.70, 0.24)
  ..lineTo(0.70, 0.30)
  ..cubicTo(0.88, 0.28, 0.94, 0.38, 0.92, 0.46) // solid handle: no enclosed
  ..cubicTo(0.90, 0.54, 0.80, 0.58, 0.68, 0.56) // hole, see header rule
  ..cubicTo(0.66, 0.62, 0.62, 0.68, 0.56, 0.72) // bowl wall to the saucer
  ..lineTo(0.78, 0.72)
  ..quadraticBezierTo(0.86, 0.72, 0.84, 0.78)
  ..quadraticBezierTo(0.70, 0.86, 0.48, 0.86) // saucer underside
  ..quadraticBezierTo(0.26, 0.86, 0.12, 0.78)
  ..quadraticBezierTo(0.10, 0.72, 0.18, 0.72)
  ..lineTo(0.28, 0.72)
  ..cubicTo(0.20, 0.64, 0.15, 0.50, 0.14, 0.24) // bowl wall back to the rim
  ..close();

Path _butterfly() => Path()
  // Big upper wings, smaller lower wings, a sharp waist notch between them
  // — the size contrast and the notch keep it from reading as an X.
  ..moveTo(0.50, 0.16) // head
  ..cubicTo(0.44, 0.10, 0.30, 0.02, 0.17, 0.06) // upper left wing
  ..cubicTo(0.04, 0.10, 0.03, 0.28, 0.10, 0.38)
  ..cubicTo(0.16, 0.46, 0.32, 0.50, 0.46, 0.50) // in to the waist
  ..cubicTo(0.28, 0.52, 0.12, 0.58, 0.10, 0.70) // lower left wing
  ..cubicTo(0.08, 0.82, 0.18, 0.90, 0.28, 0.86)
  ..cubicTo(0.38, 0.82, 0.44, 0.74, 0.47, 0.66)
  ..lineTo(0.50, 0.84) // abdomen tip
  ..lineTo(0.53, 0.66)
  ..cubicTo(0.56, 0.74, 0.62, 0.82, 0.72, 0.86) // mirrored right side
  ..cubicTo(0.82, 0.90, 0.92, 0.82, 0.90, 0.70)
  ..cubicTo(0.88, 0.58, 0.72, 0.52, 0.54, 0.50)
  ..cubicTo(0.68, 0.50, 0.84, 0.46, 0.90, 0.38)
  ..cubicTo(0.97, 0.28, 0.96, 0.10, 0.83, 0.06)
  ..cubicTo(0.70, 0.02, 0.56, 0.10, 0.50, 0.16)
  ..close();

Path _flower() {
  // A six-petal daisy: scalloped ring, petals rounded by pushing the
  // quadratic controls slightly past the tip radius.
  const petals = 6;
  const valley = 0.20, tip = 0.50;
  final step = 2 * pi / petals;
  Offset at(double angle, double r) =>
      Offset(0.5 + r * cos(angle), 0.5 + r * sin(angle));
  final path = Path();
  for (var k = 0; k < petals; k++) {
    final center = -pi / 2 + k * step;
    final start = at(center - step / 2, valley);
    if (k == 0) path.moveTo(start.dx, start.dy);
    final up = at(center - step * 0.28, tip * 1.08);
    final tipPoint = at(center, tip);
    final down = at(center + step * 0.28, tip * 1.08);
    final end = at(center + step / 2, valley);
    path
      ..quadraticBezierTo(up.dx, up.dy, tipPoint.dx, tipPoint.dy)
      ..quadraticBezierTo(down.dx, down.dy, end.dx, end.dy);
  }
  return path..close();
}

Path _leaf() => Path()
  // A bay leaf on the diagonal, pointed at both ends — the slant and the
  // two sharp tips are what make it read "leaf" instead of "tree".
  ..moveTo(0.12, 0.88) // stem-end tip
  ..cubicTo(0.12, 0.62, 0.26, 0.32, 0.50, 0.18)
  ..cubicTo(0.62, 0.11, 0.76, 0.08, 0.88, 0.12) // to the pointed tip
  ..cubicTo(0.88, 0.38, 0.74, 0.68, 0.50, 0.82)
  ..cubicTo(0.38, 0.89, 0.24, 0.92, 0.12, 0.88)
  ..close();

Path _bird() => Path()
  ..moveTo(0.05, 0.40) // beak tip
  ..lineTo(0.22, 0.30)
  ..cubicTo(0.28, 0.16, 0.48, 0.14, 0.56, 0.26) // round head
  ..cubicTo(0.62, 0.32, 0.68, 0.36, 0.74, 0.38) // back
  ..lineTo(0.95, 0.20) // tail, two tips with a notch
  ..lineTo(0.96, 0.34)
  ..lineTo(0.70, 0.52)
  ..cubicTo(0.64, 0.76, 0.40, 0.82, 0.28, 0.70) // belly
  ..cubicTo(0.16, 0.60, 0.10, 0.50, 0.05, 0.46) // chest up to the beak
  ..close();

Path _moon() {
  // Fat waxing crescent: a circle with a circular bite taken from its right.
  // Built with path ops instead of arcToPoint — the simplest route to a
  // single closed crescent contour.
  final disc = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.63, 0.5), radius: 0.45));
  final bite = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.89, 0.5), radius: 0.42));
  return Path.combine(PathOperation.difference, disc, bite);
}

Path _snowflake() {
  // Six arms, each tip forked — the fork is what separates it from a star
  // at a glance. All radii fat enough to survive small cells.
  Offset at(double angle, double r) =>
      Offset(0.5 + r * cos(angle), 0.5 + r * sin(angle));
  const valleyR = 0.15, tipR = 0.50, dipR = 0.33;
  const halfTip = 0.15, halfArm = pi / 6; // radians
  final path = Path();
  for (var k = 0; k < 6; k++) {
    final arm = -pi / 2 + k * pi / 3;
    final valley = at(arm - halfArm, valleyR);
    if (k == 0) {
      path.moveTo(valley.dx, valley.dy);
    } else {
      path.lineTo(valley.dx, valley.dy);
    }
    final tipLeft = at(arm - halfTip, tipR);
    final dip = at(arm, dipR);
    final tipRight = at(arm + halfTip, tipR);
    path
      ..lineTo(tipLeft.dx, tipLeft.dy)
      ..lineTo(dip.dx, dip.dy)
      ..lineTo(tipRight.dx, tipRight.dy);
  }
  return path..close();
}
