// Story trail art overview:
// 1. The painted vocabulary of the Story trail (owner-picked mock,
//    2026-11-22/23): hand-bent dotted path segments, dashed missing-piece
//    slots for scenes not yet found, the bow-tied kraft parcel the next
//    scene arrives in, and the faint era doodads beside the path.
// 2. Everything here is plain CustomPainters over pure geometry — no
//    widgets, no state — so the trail's looks are testable and the screen
//    file stays about behavior.
// 3. Sticker rule (ui-theme-colors.md dial 2): border and hard offset
//    shadow share ONE ink, so non-rectangular shapes draw their shadow as
//    an offset copy of their own path.

import 'package:flutter/rendering.dart';

import 'studio_theme.dart';

/// Kraft wrapping paper for the parcel; file-local like the completion
/// scrim hexes — nothing else in the app wraps anything.
const kraftPaper = Color(0xFFE8D8B2);

/// One dotted trail segment: a lazy S-curve from the previous stop's
/// center-bottom to the next stop's center-top, inside this painter's box.
class TrailSegmentPainter extends CustomPainter {
  const TrailSegmentPainter({
    required this.fromX,
    required this.toX,
    this.opacity = 1,
    this.dotRadius = 2.5,
    this.spacing = 15,
    this.pop = 1,
    this.lit = 0,
    super.repaint,
  });

  /// Horizontal start/end as fractions of the box width.
  final double fromX;
  final double toX;

  /// Future segments fade; read segments are full ink.
  final double opacity;

  final double dotRadius;
  final double spacing;

  /// Unlock reveal: 0 → no dots yet, 1 → all landed. Dots pop in walking
  /// order, each with a small overshoot.
  final double pop;

  /// Finale light-up: the first [lit] fraction of the segment glows full
  /// ink regardless of [opacity].
  final double lit;

  @override
  void paint(Canvas canvas, Size size) {
    final dots = segmentDots(size, fromX: fromX, toX: toX, spacing: spacing);
    final base = Paint()
      ..color = StudioColors.structureInk.withValues(alpha: opacity);
    final glow = Paint()..color = StudioColors.structureInk;
    for (var i = 0; i < dots.length; i++) {
      // Stagger: dot i owns a window of the pop timeline, finishing with a
      // 1.3x overshoot like the mock's keyframes.
      final t = (pop * dots.length - i).clamp(0.0, 1.0);
      if (t == 0) {
        continue;
      }
      final overshoot = t < 0.7 ? t / 0.7 * 1.3 : 1.3 - (t - 0.7) / 0.3 * 0.3;
      final isLit = lit > 0 && i / dots.length < lit;
      canvas.drawCircle(
        dots[i],
        dotRadius * overshoot * (isLit ? 1.25 : 1),
        isLit ? glow : base,
      );
    }
  }

  @override
  bool shouldRepaint(TrailSegmentPainter old) =>
      old.fromX != fromX ||
      old.toX != toX ||
      old.opacity != opacity ||
      old.pop != pop ||
      old.lit != lit;
}

/// Dot centers for a segment box — pure, so tests can pin the geometry.
/// The curve bulges sideways mid-band, which is what makes the trail read
/// as hand-laid instead of ruled.
List<Offset> segmentDots(
  Size size, {
  required double fromX,
  required double toX,
  double spacing = 15,
}) {
  final start = Offset(size.width * fromX, 4);
  final end = Offset(size.width * toX, size.height - 4);
  final sway = (end.dx - start.dx) * 0.42;
  final path = Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      start.dx + sway,
      start.dy + (end.dy - start.dy) * 0.38,
      end.dx - sway,
      start.dy + (end.dy - start.dy) * 0.62,
      end.dx,
      end.dy,
    );
  final metric = path.computeMetrics().first;
  return [
    for (var d = 0.0; d <= metric.length; d += spacing)
      metric.getTangentForOffset(d)!.position,
  ];
}

/// A scene not found yet: a dashed, empty puzzle-piece slot with its hard
/// offset shadow (the owner's pick C over parcel variants).
class MissingPieceSlotPainter extends CustomPainter {
  const MissingPieceSlotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final piece = pieceSlotPath(size);
    final shadowShift = size.width / 26;
    canvas.drawPath(
      piece.shift(Offset(shadowShift, shadowShift)),
      Paint()..color = StudioColors.structureInk.withValues(alpha: 0.9),
    );
    canvas.drawPath(piece, Paint()..color = StudioColors.card);
    canvas.drawPath(
      dashPath(piece, dash: size.width / 15, gap: size.width / 19),
      Paint()
        ..color = StudioColors.structureInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(MissingPieceSlotPainter old) => false;
}

/// The slot's puzzle-piece outline (knob up top, knob to the right),
/// scaled from the approved 132-unit mock drawing.
Path pieceSlotPath(Size size) {
  final s = size.width / 132;
  Offset p(double x, double y) => Offset(x * s, y * s);
  return Path()
    ..moveTo(24 * s, 40 * s)
    ..lineTo(46 * s, 40 * s)
    ..cubicTo(43 * s, 25 * s, 54 * s, 17 * s, 66 * s, 17 * s)
    ..cubicTo(78 * s, 17 * s, 89 * s, 25 * s, 86 * s, 40 * s)
    ..lineTo(108 * s, 40 * s)
    ..lineTo(108 * s, 62 * s)
    ..cubicTo(123 * s, 59 * s, 131 * s, 70 * s, 131 * s, 82 * s)
    ..cubicTo(131 * s, 94 * s, 123 * s, 105 * s, 108 * s, 102 * s)
    ..lineTo(p(108, 124).dx, p(108, 124).dy)
    ..lineTo(24 * s, 124 * s)
    ..close();
}

/// The next scene's delivery: kraft paper tied corner-to-corner with a
/// bow knot (replaces the twine-cross the owner called a window).
class TiedParcelPainter extends CustomPainter {
  const TiedParcelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 132;
    final rect = Rect.fromLTWH(10 * s, 10 * s, 104 * s, 104 * s);
    final radius = Radius.circular(13 * s);
    final shadow = Offset(4 * s, 4 * s);
    final ink = Paint()..color = StudioColors.structureInk;
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(shadow), radius), ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = kraftPaper,
    );
    final border = Paint()
      ..color = StudioColors.structureInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), border);
    // Ribbons corner to corner, clipped to the paper so the X never pokes
    // past the rounded corners.
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(rect, radius));
    final ribbon = Paint()
      ..color = StudioColors.structureInk.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * s
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(rect.topLeft, rect.bottomRight, ribbon)
      ..drawLine(rect.topRight, rect.bottomLeft, ribbon)
      ..restore();
    // The bow: two loops, two tails, a knot — ported from the mock paths.
    final bow = Paint()
      ..color = StudioColors.structureInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round;
    final loops = Path()
      ..moveTo(58 * s, 60 * s)
      ..quadraticBezierTo(40 * s, 46 * s, 46 * s, 58 * s)
      ..quadraticBezierTo(49 * s, 65 * s, 58 * s, 63 * s)
      ..moveTo(66 * s, 60 * s)
      ..quadraticBezierTo(84 * s, 46 * s, 78 * s, 58 * s)
      ..quadraticBezierTo(75 * s, 65 * s, 66 * s, 63 * s)
      ..moveTo(60 * s, 66 * s)
      ..lineTo(54 * s, 78 * s)
      ..moveTo(64 * s, 66 * s)
      ..lineTo(69 * s, 77 * s);
    canvas
      ..drawPath(loops, bow)
      ..drawCircle(Offset(62 * s, 61 * s), 4.5 * s, ink);
  }

  @override
  bool shouldRepaint(TiedParcelPainter old) => false;
}

/// The faint trail-side scenery, one per stretch of history.
enum TrailDoodad { map, globe, fretsaw, box, teacup }

class DoodadPainter extends CustomPainter {
  const DoodadPainter(this.kind);

  final TrailDoodad kind;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 60;
    final stroke = Paint()
      ..color = StudioColors.structureInk.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) => Offset(x * s, y * s);
    switch (kind) {
      case TrailDoodad.map:
        canvas.drawPath(
          Path()
            ..moveTo(p(8, 12).dx, p(8, 12).dy)
            ..lineTo(p(22, 7).dx, p(22, 7).dy)
            ..lineTo(p(38, 12).dx, p(38, 12).dy)
            ..lineTo(p(52, 7).dx, p(52, 7).dy)
            ..lineTo(p(52, 36).dx, p(52, 36).dy)
            ..lineTo(p(38, 41).dx, p(38, 41).dy)
            ..lineTo(p(22, 36).dx, p(22, 36).dy)
            ..lineTo(p(8, 41).dx, p(8, 41).dy)
            ..close()
            ..moveTo(p(22, 7).dx, p(22, 7).dy)
            ..lineTo(p(22, 36).dx, p(22, 36).dy)
            ..moveTo(p(38, 12).dx, p(38, 12).dy)
            ..lineTo(p(38, 41).dx, p(38, 41).dy),
          stroke,
        );
        canvas.drawPath(
          dashPath(
            Path()
              ..moveTo(p(14, 28).dx, p(14, 28).dy)
              ..quadraticBezierTo(
                p(19, 20).dx,
                p(19, 20).dy,
                p(26, 24).dx,
                p(26, 24).dy,
              )
              ..quadraticBezierTo(
                p(33, 28).dx,
                p(33, 28).dy,
                p(40, 19).dx,
                p(40, 19).dy,
              ),
            dash: 3 * s,
            gap: 4 * s,
          ),
          stroke,
        );
      case TrailDoodad.globe:
        canvas
          ..drawCircle(p(30, 24), 18 * s, stroke)
          ..drawOval(
            Rect.fromCenter(center: p(30, 24), width: 16 * s, height: 36 * s),
            stroke,
          )
          ..drawOval(
            Rect.fromCenter(center: p(30, 24), width: 36 * s, height: 13 * s),
            stroke,
          )
          ..drawLine(p(30, 42), p(30, 48), stroke)
          ..drawPath(
            Path()
              ..moveTo(p(20, 48).dx, p(20, 48).dy)
              ..quadraticBezierTo(
                p(30, 53).dx,
                p(30, 53).dy,
                p(40, 48).dx,
                p(40, 48).dy,
              ),
            stroke,
          );
      case TrailDoodad.fretsaw:
        final teeth = Path()..moveTo(p(16, 10).dx, p(16, 10).dy);
        for (var y = 14; y <= 42; y += 8) {
          teeth
            ..lineTo(p(21, y - 4).dx, p(21, y - 4).dy)
            ..lineTo(p(16, y.toDouble()).dx, p(16, y.toDouble()).dy);
        }
        canvas
          ..drawPath(teeth, stroke)
          ..drawPath(
            Path()
              ..moveTo(p(16, 10).dx, p(16, 10).dy)
              ..cubicTo(
                p(44, 6).dx,
                p(44, 6).dy,
                p(52, 18).dx,
                p(52, 18).dy,
                p(50, 26).dx,
                p(50, 26).dy,
              )
              ..cubicTo(
                p(52, 34).dx,
                p(52, 34).dy,
                p(44, 46).dx,
                p(44, 46).dy,
                p(16, 42).dx,
                p(16, 42).dy,
              ),
            stroke,
          )
          ..drawLine(
            p(16, 42),
            p(12, 54),
            Paint()
              ..color = stroke.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4.5
              ..strokeCap = StrokeCap.round,
          );
      case TrailDoodad.box:
        canvas
          ..drawPath(
            Path()
              ..addRect(Rect.fromPoints(p(14, 24), p(46, 46)))
              ..moveTo(p(14, 24).dx, p(14, 24).dy)
              ..lineTo(p(5, 13).dx, p(5, 13).dy)
              ..lineTo(p(18, 16).dx, p(18, 16).dy)
              ..moveTo(p(46, 24).dx, p(46, 24).dy)
              ..lineTo(p(55, 13).dx, p(55, 13).dy)
              ..lineTo(p(42, 16).dx, p(42, 16).dy),
            stroke,
          )
          ..drawPath(
            dashPath(
              Path()
                ..moveTo(p(30, 24).dx, p(30, 24).dy)
                ..lineTo(p(30, 46).dx, p(30, 46).dy),
              dash: 3 * s,
              gap: 3 * s,
            ),
            stroke,
          );
      case TrailDoodad.teacup:
        canvas.drawPath(
          Path()
            ..moveTo(p(14, 26).dx, p(14, 26).dy)
            ..quadraticBezierTo(
              p(14, 41).dx,
              p(14, 41).dy,
              p(30, 41).dx,
              p(30, 41).dy,
            )
            ..quadraticBezierTo(
              p(46, 41).dx,
              p(46, 41).dy,
              p(46, 26).dx,
              p(46, 26).dy,
            )
            ..close()
            ..moveTo(p(46, 28).dx, p(46, 28).dy)
            ..quadraticBezierTo(
              p(54, 28).dx,
              p(54, 28).dy,
              p(52, 34).dx,
              p(52, 34).dy,
            )
            ..quadraticBezierTo(
              p(50, 39).dx,
              p(50, 39).dy,
              p(44, 37).dx,
              p(44, 37).dy,
            )
            ..moveTo(p(11, 44).dx, p(11, 44).dy)
            ..lineTo(p(49, 44).dx, p(49, 44).dy)
            ..moveTo(p(24, 20).dx, p(24, 20).dy)
            ..quadraticBezierTo(
              p(27, 15).dx,
              p(27, 15).dy,
              p(24, 10).dx,
              p(24, 10).dy,
            )
            ..moveTo(p(34, 20).dx, p(34, 20).dy)
            ..quadraticBezierTo(
              p(37, 15).dx,
              p(37, 15).dy,
              p(34, 10).dx,
              p(34, 10).dy,
            ),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(DoodadPainter old) => old.kind != kind;
}

/// Rebuilds [source] as dashes — Flutter has no dashed stroke primitive,
/// so the path is walked by its metrics.
Path dashPath(Path source, {required double dash, required double gap}) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      result.addPath(
        metric.extractPath(d, (d + dash).clamp(0, metric.length)),
        Offset.zero,
      );
      d += dash + gap;
    }
  }
  return result;
}
