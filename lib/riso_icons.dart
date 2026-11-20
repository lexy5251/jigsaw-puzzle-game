// The hand-bent riso icon set (reference: docs/design/icon-set-final.png,
// decided through mock rounds v24–v26b). Paths are hand-translations of the
// reference SVGs on their 48-unit grid: no straight lines, no perfect
// circles — frames bow, circles wobble, strokes bend. One stroke weight,
// round caps. Rendered as CustomPainters like the studio mascots — no SVG
// dependency.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'studio_theme.dart';

/// Every glyph in the set. Names follow the icon reference sheet.
enum RisoGlyph {
  /// A framed little painting — the Gallery tab.
  gallery,

  /// An open book — the Story tab.
  story,

  /// The family-A puzzle piece, outline — the My Puzzles tab at rest.
  piece,

  /// The family-A puzzle piece, filled — active nav / markers. Uses the
  /// EXACT marker path so nav and card markers stay one shape.
  pieceFilled,

  /// Two sliders — the Settings tab (it's literally what the page is).
  sliders,

  /// A dashed "ghost picture" — the image-preview toggle (play + setting).
  imagePreview,

  /// Chunky bouncing ⋯ — the Options menu trigger.
  options,

  /// Magnifier with a plus — Zoom in.
  zoomIn,

  /// A loop arrow — Start over.
  startOver,

  /// A solid puzzle piece with a FLAT BOTTOM on a faint ground line —
  /// the Edges-only filter (an edge piece, the jigsaw player's own word).
  edgePiece,

  /// A broom — Tidy (owner's pick over the download-look tray arrow).
  broom,

  /// A speaker horn with two arcs — effect sounds.
  speaker,

  /// A wobbly eighth-note pair — music.
  music,

  /// A phone with buzz waves — vibrate on snap.
  vibrate,

  /// Hand-bent back arrow — stands alone (universal).
  back,

  /// Hand-bent forward arrow — the Next-puzzle button.
  forward,
}

/// A glyph from the riso set, sized like an [Icon] and colored from the
/// ambient [IconTheme] unless overridden.
class RisoIcon extends StatelessWidget {
  const RisoIcon(this.glyph, {super.key, this.size = 24, this.color});

  final RisoGlyph glyph;
  final double size;

  /// Stroke/fill ink; defaults to the surrounding IconTheme's color (so
  /// nav/tab selected states keep working), then to the text ink.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? StudioColors.ink;
    return CustomPaint(
      size: Size.square(size),
      painter: _RisoIconPainter(glyph: glyph, ink: ink),
    );
  }
}

/// The marker path shared by [RisoGlyph.pieceFilled] and every piece-family
/// marker (done stickers, streak pieces, the "N of 10" meter). One source
/// so the shapes cannot drift apart. Drawn on the 48-unit grid.
Path familyPiecePath() {
  return Path()
    ..moveTo(10, 16)
    ..relativeLineTo(8, 0)
    ..relativeCubicTo(0, -7, 8, -7, 8, 0)
    ..relativeLineTo(12, 0)
    ..relativeLineTo(0, 10)
    ..relativeCubicTo(7, 0, 7, 8, 0, 8)
    ..relativeLineTo(0, 10)
    ..relativeLineTo(-8, 0)
    ..relativeCubicTo(0, 7, -8, 7, -8, 0)
    ..relativeLineTo(-12, 0)
    ..close();
}

class _RisoIconPainter extends CustomPainter {
  const _RisoIconPainter({required this.glyph, required this.ink});

  final RisoGlyph glyph;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    canvas
      ..save()
      ..scale(scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    final fill = Paint()..color = ink;
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = ink.withValues(alpha: 0.5);

    switch (glyph) {
      case RisoGlyph.gallery:
        _gallery(canvas, stroke, fill);
      case RisoGlyph.story:
        _story(canvas, stroke, faint);
      case RisoGlyph.piece:
        _piece(canvas, stroke);
      case RisoGlyph.pieceFilled:
        _pieceFilled(canvas, fill);
      case RisoGlyph.sliders:
        _sliders(canvas, stroke, fill);
      case RisoGlyph.imagePreview:
        _imagePreview(canvas, stroke);
      case RisoGlyph.options:
        _options(canvas, fill);
      case RisoGlyph.zoomIn:
        _zoomIn(canvas, stroke);
      case RisoGlyph.startOver:
        _startOver(canvas, stroke);
      case RisoGlyph.edgePiece:
        _edgePiece(canvas, fill, faint);
      case RisoGlyph.broom:
        _broom(canvas, stroke, fill, faint);
      case RisoGlyph.speaker:
        _speaker(canvas, stroke, fill);
      case RisoGlyph.music:
        _music(canvas, stroke, fill);
      case RisoGlyph.vibrate:
        _vibrate(canvas, stroke);
      case RisoGlyph.back:
        _arrow(canvas, stroke, pointsLeft: true);
      case RisoGlyph.forward:
        _arrow(canvas, stroke, pointsLeft: false);
    }
    canvas.restore();
  }

  /// The bowed rounded frame several glyphs share (gallery, preview).
  static Path _bowedFrame() => Path()
    ..moveTo(8, 10)
    ..cubicTo(19, 8.6, 30, 9, 40, 10)
    ..cubicTo(41, 18, 41, 28, 40, 36)
    ..cubicTo(29, 37.4, 18, 37, 8, 36)
    ..cubicTo(7, 28, 7, 18, 8, 10)
    ..close();

  /// The little hill line inside the picture glyphs.
  static Path _hills() => Path()
    ..moveTo(12.5, 30.5)
    ..cubicTo(15.5, 26, 18, 23, 20.3, 21.4)
    ..cubicTo(22.3, 23.5, 23.7, 25.2, 25.2, 26.8)
    ..cubicTo(27.5, 23.2, 29.6, 20.4, 31.6, 18.8)
    ..cubicTo(33.6, 22.2, 35.4, 26.4, 36.6, 30.2);

  void _gallery(Canvas canvas, Paint stroke, Paint fill) {
    canvas
      ..drawPath(_bowedFrame(), stroke)
      ..drawPath(_hills(), stroke)
      ..drawOval(
        Rect.fromCenter(
          center: const Offset(31.6, 14.3),
          width: 5.4,
          height: 5,
        ),
        fill,
      );
  }

  void _story(Canvas canvas, Paint stroke, Paint faint) {
    final cover = Path()
      ..moveTo(24, 13.5)
      ..cubicTo(20.4, 9.6, 13, 9, 7.6, 11.6)
      ..cubicTo(7.1, 19.6, 7.1, 27.6, 7.9, 35.6)
      ..cubicTo(13, 33.2, 20, 33.6, 24, 37.2)
      ..cubicTo(28, 33.6, 35, 33.2, 40.1, 35.6)
      ..cubicTo(40.9, 27.6, 40.9, 19.6, 40.4, 11.6)
      ..cubicTo(35, 9, 27.6, 9.6, 24, 13.5)
      ..close();
    final spine = Path()
      ..moveTo(24, 14)
      ..cubicTo(23.6, 21, 23.7, 29, 24, 36.6);
    final lines = Path()
      ..moveTo(11.5, 16.5)
      ..cubicTo(14.5, 15.6, 17.5, 15.6, 20, 16.4)
      ..moveTo(11.5, 21.5)
      ..cubicTo(14.5, 20.7, 17.5, 20.7, 20, 21.4);
    canvas
      ..drawPath(cover, stroke)
      ..drawPath(spine, stroke)
      ..drawPath(lines, faint..strokeWidth = 2.4);
  }

  void _piece(Canvas canvas, Paint stroke) {
    // The looser hand-bent outline (reads at ≥24px; small filled contexts
    // use the exact marker path instead).
    final piece = Path()
      ..moveTo(10.5, 16.5)
      ..cubicTo(13, 16.1, 15.6, 16, 18.2, 16.2)
      ..cubicTo(17.8, 9.6, 25.8, 9.2, 26, 15.8)
      ..cubicTo(29.8, 15.6, 33.6, 15.8, 37.6, 16.4)
      ..cubicTo(38, 19.6, 38.1, 22.6, 38, 25.6)
      ..cubicTo(44.4, 25.4, 44.4, 33.2, 38.1, 33.4)
      ..cubicTo(38.2, 36.6, 38, 40, 37.6, 43.4)
      ..cubicTo(35, 43.8, 32.4, 44, 29.8, 43.8)
      ..cubicTo(30.4, 50.2, 22.2, 50.6, 22.2, 44)
      ..cubicTo(18.4, 44.2, 14.6, 44, 10.6, 43.4)
      ..cubicTo(10, 34.4, 10, 25.4, 10.5, 16.5)
      ..close();
    canvas
      ..save()
      ..translate(4.1, -4.1)
      ..scale(0.82)
      ..drawPath(piece, stroke..strokeWidth = 3.2)
      ..restore();
  }

  void _pieceFilled(Canvas canvas, Paint fill) {
    canvas
      ..save()
      ..translate(24, 24)
      ..rotate(3 * math.pi / 180)
      ..translate(-24, -24)
      ..drawPath(familyPiecePath(), fill)
      ..restore();
  }

  void _sliders(Canvas canvas, Paint stroke, Paint fill) {
    final lines = Path()
      ..moveTo(8.5, 16.3)
      ..cubicTo(18.5, 15.2, 29.5, 15.4, 39.5, 16.2)
      ..moveTo(8.5, 32.3)
      ..cubicTo(18.5, 31.2, 29.5, 31.4, 39.5, 32.2);
    canvas.drawPath(lines, stroke);
    // Knobs: ground-filled so they sit "on" the line, with the ink rim.
    final knobFill = Paint()..color = StudioColors.ground;
    for (final (cx, cy) in [(30.0, 15.7), (17.0, 31.7)]) {
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: 9.6,
        height: 8.8,
      );
      canvas
        ..drawOval(rect, knobFill)
        ..drawOval(rect, stroke);
    }
  }

  void _imagePreview(Canvas canvas, Paint stroke) {
    canvas
      ..drawPath(_dashed(_bowedFrame(), 5.5, 5), stroke)
      ..drawPath(
        _hills(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ink.withValues(alpha: 0.55),
      );
  }

  void _options(Canvas canvas, Paint fill) {
    for (final (cx, cy, r) in [(12.0, 24.4, 3.4), (24.0, 23.0, 3.6), (36.0, 24.6, 3.4)]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 2 * r, height: 2 * r - 0.5),
        fill,
      );
    }
  }

  void _zoomIn(Canvas canvas, Paint stroke) {
    final lens = Path()
      ..moveTo(20, 9.5)
      ..cubicTo(26.5, 9, 31, 13.8, 31, 20)
      ..cubicTo(31, 26, 26.2, 30.8, 20.2, 30.6)
      ..cubicTo(14.2, 30.4, 9.7, 25.8, 9.9, 19.8)
      ..cubicTo(10.1, 14, 14, 10, 20, 9.5)
      ..close();
    final rest = Path()
      ..moveTo(29.5, 29.5)
      ..cubicTo(33, 32.8, 36.5, 36.3, 39.8, 40.2)
      ..moveTo(20.2, 15.3)
      ..cubicTo(20, 18.4, 20, 21.5, 20.2, 24.7)
      ..moveTo(15.3, 20.2)
      ..cubicTo(18.4, 19.9, 21.5, 19.9, 24.7, 20.1);
    canvas
      ..drawPath(lens, stroke)
      ..drawPath(rest, stroke);
  }

  void _startOver(Canvas canvas, Paint stroke) {
    final loop = Path()
      ..moveTo(35.5, 15)
      ..cubicTo(31, 9.6, 23, 8.2, 16.8, 11.6)
      ..cubicTo(10.4, 15.6, 7.9, 23.6, 10.9, 30)
      ..cubicTo(13.9, 36.4, 21.4, 39.8, 28.2, 37.8)
      ..cubicTo(33.7, 36.2, 37.8, 32, 38.9, 26.8)
      ..moveTo(35.8, 6.2)
      ..cubicTo(35.7, 9.4, 35.7, 12.6, 35.8, 15.8)
      ..moveTo(26.2, 13.8)
      ..cubicTo(29.4, 14.4, 32.6, 15, 35.7, 15.6);
    canvas.drawPath(loop, stroke);
  }

  void _edgePiece(Canvas canvas, Paint fill, Paint faint) {
    final piece = Path()
      ..moveTo(10.5, 36)
      ..cubicTo(10.2, 29, 10.2, 22, 10.7, 15.5)
      ..cubicTo(13.6, 15, 16.4, 14.9, 19, 15.1)
      ..cubicTo(18.6, 9, 25.8, 8.6, 26, 14.7)
      ..cubicTo(29.8, 14.5, 33.6, 14.8, 37.4, 15.4)
      ..cubicTo(37.9, 22.2, 38, 29, 37.6, 36)
      ..close();
    final groundLine = Path()
      ..moveTo(8, 42.5)
      ..cubicTo(18.5, 41.6, 29.5, 41.8, 40, 42.4);
    canvas
      ..drawPath(piece, fill)
      ..drawPath(groundLine, faint);
  }

  void _broom(Canvas canvas, Paint stroke, Paint fill, Paint faint) {
    final handle = Path()
      ..moveTo(38.5, 6)
      ..cubicTo(33.4, 11.8, 28.4, 17.6, 23.6, 23.4);
    final head = Path()
      ..moveTo(23.6, 23.4)
      ..cubicTo(20.2, 26.4, 16.8, 29.4, 14.1, 31.9)
      ..cubicTo(12.1, 33.9, 12.3, 36.1, 14.3, 37.9)
      ..lineTo(20, 42.2)
      ..cubicTo(22, 43.5, 24.2, 43.1, 25.4, 41.1)
      ..cubicTo(27.3, 37.9, 29.2, 34.5, 31, 31)
      ..close();
    final specks = Path()
      ..moveTo(9, 44.3)
      ..relativeCubicTo(1, -0.4, 2, -0.5, 3, -0.3)
      ..moveTo(15.5, 46)
      ..relativeCubicTo(1.3, -0.3, 2.6, -0.3, 3.9, -0.1);
    canvas
      ..drawPath(handle, stroke)
      ..drawPath(head, fill)
      ..drawPath(specks, faint);
  }

  void _speaker(Canvas canvas, Paint stroke, Paint fill) {
    final horn = Path()
      ..moveTo(9.5, 19.5)
      ..cubicTo(11.8, 19.1, 14, 19, 16, 19.2)
      ..cubicTo(18.8, 16.5, 21.7, 13.9, 24.8, 11.3)
      ..cubicTo(25.3, 19.8, 25.3, 28.3, 24.8, 36.7)
      ..cubicTo(21.7, 34.1, 18.8, 31.5, 16, 28.8)
      ..cubicTo(14, 29, 11.8, 28.9, 9.5, 28.5)
      ..cubicTo(9.1, 25.5, 9.1, 22.5, 9.5, 19.5)
      ..close();
    final waves = Path()
      ..moveTo(30.8, 18)
      ..cubicTo(33.6, 21.8, 33.7, 26.2, 31.1, 30.1)
      ..moveTo(35.2, 13.8)
      ..cubicTo(39.6, 19.8, 39.7, 28, 35.5, 34.2);
    canvas
      ..drawPath(horn, fill)
      ..drawPath(waves, stroke);
  }

  void _music(Canvas canvas, Paint stroke, Paint fill) {
    final beam = Path()
      ..moveTo(19.5, 34)
      ..cubicTo(19.2, 27, 19.2, 20, 19.6, 13.2)
      ..cubicTo(25, 11.6, 30.4, 10.2, 35.8, 9)
      ..cubicTo(36.1, 16, 36.1, 23, 35.8, 30);
    canvas.drawPath(beam, stroke);
    for (final (cx, cy) in [(15.2, 35.2), (31.8, 31.2)]) {
      canvas
        ..save()
        ..translate(cx, cy)
        ..rotate(-10 * math.pi / 180)
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: 9.4, height: 8.4),
          fill,
        )
        ..restore();
    }
  }

  void _vibrate(Canvas canvas, Paint stroke) {
    final phone = Path()
      ..moveTo(17.8, 10)
      ..cubicTo(21.8, 9.3, 26.2, 9.3, 30.3, 10)
      ..cubicTo(31, 19.4, 31, 28.8, 30.3, 38.2)
      ..cubicTo(26.2, 38.9, 21.8, 38.9, 17.8, 38.2)
      ..cubicTo(17.1, 28.8, 17.1, 19.4, 17.8, 10)
      ..close();
    final waves = Path()
      ..moveTo(9.3, 17.3)
      ..relativeCubicTo(-3, 3.7, -3, 9.9, 0.4, 13.5)
      ..moveTo(38.7, 17.3)
      ..relativeCubicTo(3, 3.7, 3, 9.9, -0.4, 13.5);
    canvas
      ..save()
      ..translate(24, 24)
      ..rotate(2 * math.pi / 180)
      ..translate(-24, -24)
      ..drawPath(phone, stroke)
      ..restore()
      ..drawPath(waves, stroke);
  }

  void _arrow(Canvas canvas, Paint stroke, {required bool pointsLeft}) {
    final shaft = Path()
      ..moveTo(40, 25)
      ..cubicTo(30, 23, 20, 23, 10, 24);
    final head = Path()
      ..moveTo(19, 14)
      ..cubicTo(15, 18, 12, 21, 9, 24)
      ..cubicTo(12, 27, 15, 30, 19, 34);
    if (!pointsLeft) {
      canvas
        ..translate(48, 0)
        ..scale(-1, 1);
    }
    canvas
      ..drawPath(shaft, stroke..strokeWidth = 3.2)
      ..drawPath(head, stroke);
  }

  /// Converts a path to its dashed version — Canvas has no dash support.
  static Path _dashed(Path source, double dash, double gap) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(_RisoIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.ink != ink;
}
