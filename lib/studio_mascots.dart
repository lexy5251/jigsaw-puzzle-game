// The painted motif cast of the Studio look (docs/design/brushwork-mockup.html):
// cactus, sunflower, daisy, palette, and the six category mascots. The mockup
// defines them as small SVG symbols; this file is their hand translation to
// Canvas calls — same coordinates, same fills — so they ship without an SVG
// dependency. Each painter draws in its symbol's viewBox and is scaled to fit.

import 'package:flutter/material.dart';

/// Every painted motif. `pot` is the unbloomed windowsill day; `sprig` is the
/// potted sunflower under the completion plaque; `sprout` is the growing stem
/// that marks a puzzle in progress.
enum StudioMascot {
  pot,
  cactus,
  sunflower,
  daisy,
  mountains,
  mug,
  cat,
  houses,
  palette,
  sprig,
  sprout,
}

/// Category mascots (mockup section F). Keys match `PuzzleCategory.id`;
/// a test keeps the two in sync.
const categoryMascots = <String, StudioMascot>{
  'landscapes': StudioMascot.mountains,
  'cozy': StudioMascot.mug,
  'animals': StudioMascot.cat,
  'flowers': StudioMascot.daisy,
  'cities': StudioMascot.houses,
  'art': StudioMascot.palette,
};

/// Falls back to the palette (the generic "art" motif) so an unstyled new
/// category degrades gracefully, mirroring `categoryStyleFor`.
StudioMascot mascotForCategory(String categoryId) =>
    categoryMascots[categoryId] ?? StudioMascot.palette;

/// One motif at a given height; width follows the motif's own aspect ratio.
class MascotArt extends StatelessWidget {
  const MascotArt(this.mascot, {super.key, required this.height});

  final StudioMascot mascot;
  final double height;

  @override
  Widget build(BuildContext context) {
    final box = _viewBox(mascot);
    return CustomPaint(
      size: Size(height * box.width / box.height, height),
      painter: _MascotPainter(mascot),
    );
  }
}

Size _viewBox(StudioMascot mascot) => switch (mascot) {
  StudioMascot.pot ||
  StudioMascot.cactus ||
  StudioMascot.daisy ||
  StudioMascot.sprout => const Size(48, 64),
  StudioMascot.sprig => const Size(48, 70),
  StudioMascot.mountains || StudioMascot.houses => const Size(96, 64),
  _ => const Size(64, 64),
};

class _MascotPainter extends CustomPainter {
  const _MascotPainter(this.mascot);

  final StudioMascot mascot;

  @override
  void paint(Canvas canvas, Size size) {
    final box = _viewBox(mascot);
    canvas.scale(size.width / box.width, size.height / box.height);
    switch (mascot) {
      case StudioMascot.pot:
        _pot(canvas);
      case StudioMascot.cactus:
        _cactus(canvas);
      case StudioMascot.sunflower:
        _sunflower(canvas);
      case StudioMascot.daisy:
        _daisy(canvas);
      case StudioMascot.mountains:
        _mountains(canvas);
      case StudioMascot.mug:
        _mug(canvas);
      case StudioMascot.cat:
        _cat(canvas);
      case StudioMascot.houses:
        _houses(canvas);
      case StudioMascot.palette:
        _palette(canvas);
      case StudioMascot.sprig:
        _sprig(canvas);
      case StudioMascot.sprout:
        _sprout(canvas);
    }
  }

  @override
  bool shouldRepaint(_MascotPainter oldDelegate) =>
      oldDelegate.mascot != mascot;
}

Paint _fill(int argb) => Paint()..color = Color(argb);

Paint _stroke(int argb, double width) => Paint()
  ..color = Color(argb)
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round;

void _rrect(
  Canvas canvas,
  double x,
  double y,
  double w,
  double h,
  double r,
  int argb,
) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
    _fill(argb),
  );
}

void _polygon(Canvas canvas, List<Offset> points, int argb) {
  canvas.drawPath(Path()..addPolygon(points, true), _fill(argb));
}

void _oval(Canvas canvas, double cx, double cy, double rx, double ry, int argb,
    {double rotationDegrees = 0}) {
  canvas.save();
  canvas.translate(cx, cy);
  canvas.rotate(rotationDegrees * 3.1415926535 / 180);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
    _fill(argb),
  );
  canvas.restore();
}

// ---- motifs (coordinates mirror the mockup's SVG symbols) ----

void _pot(Canvas canvas) {
  _polygon(canvas, const [
    Offset(14, 45),
    Offset(34, 45),
    Offset(31, 60),
    Offset(17, 60),
  ], 0xFFC97B4F);
  _rrect(canvas, 12, 42, 24, 6, 3, 0xFFB06A42);
}

void _cactus(Canvas canvas) {
  // Arms sit behind the pot rim, like the SVG paint order.
  _rrect(canvas, 20, 12, 9, 32, 4.5, 0xFF7B8A58); // trunk
  _rrect(canvas, 10, 20, 7, 14, 3.5, 0xFF86935F); // left arm
  _rrect(canvas, 13, 28, 10, 6, 3, 0xFF86935F); // left joint
  _rrect(canvas, 32, 16, 7, 17, 3.5, 0xFF6F7E4E); // right arm
  _rrect(canvas, 26, 27, 10, 6, 3, 0xFF6F7E4E); // right joint
  canvas.drawCircle(const Offset(24.5, 10), 4, _fill(0xFFD79B86)); // bloom
  _pot(canvas);
}

void _sunflower(Canvas canvas) {
  // Twelve petals around the head, one ellipse rotated in 30° steps.
  for (var i = 0; i < 12; i++) {
    canvas.save();
    canvas.translate(32, 32);
    canvas.rotate(i * 3.1415926535 / 6);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -21), width: 10, height: 20),
      _fill(0xFFD9A33F),
    );
    canvas.restore();
  }
  canvas.drawCircle(const Offset(32, 32), 10.5, _fill(0xFF6B4F2E));
  for (final seed in const [Offset(28.5, 30), Offset(35, 33.5), Offset(31, 35.5)]) {
    canvas.drawCircle(seed, 1.4, _fill(0xFF8A6B43));
  }
}

void _daisy(Canvas canvas) {
  // One flower from the mockup's daisy border, upright on its stem.
  canvas.drawPath(
    Path()
      ..moveTo(24, 32)
      ..quadraticBezierTo(27, 46, 24, 58),
    _stroke(0xFF7B8456, 2.5),
  );
  _oval(canvas, 17.5, 46, 5.5, 2.8, 0xFF86935F, rotationDegrees: -24);
  // Three crossing ellipses read as six petals.
  for (final degrees in const [0.0, 60.0, 120.0]) {
    _oval(canvas, 24, 19, 4.5, 10.5, 0xFFE0AB96, rotationDegrees: degrees);
  }
  canvas.drawCircle(const Offset(24, 19), 4, _fill(0xFFD9A33F));
}

void _mountains(Canvas canvas) {
  canvas.drawCircle(const Offset(76, 16), 9, _fill(0xFFD9A33F)); // sun
  _polygon(canvas, const [
    Offset(4, 58),
    Offset(32, 18),
    Offset(50, 44),
    Offset(58, 33),
    Offset(82, 58),
  ], 0xFF86935F);
  _polygon(canvas, const [
    Offset(36, 58),
    Offset(58, 26),
    Offset(82, 58),
  ], 0xFF5F7050);
}

void _mug(Canvas canvas) {
  _oval(canvas, 29, 55, 18, 3, 0x73B06A42); // saucer shadow, 45% alpha
  for (final x in const [22.0, 32.0]) {
    canvas.drawPath(
      Path()
        ..moveTo(x, 16)
        ..cubicTo(x - 2, 12, x + 2, 10, x, 6),
      _stroke(0xFFB9A98E, 2.5),
    );
  }
  canvas.drawPath(
    Path()
      ..moveTo(14, 24)
      ..lineTo(42, 24)
      ..lineTo(42, 40)
      ..arcToPoint(const Offset(32, 50), radius: const Radius.circular(10))
      ..lineTo(24, 50)
      ..arcToPoint(const Offset(14, 40), radius: const Radius.circular(10))
      ..close(),
    _fill(0xFFC06A45),
  );
  canvas.drawPath(
    Path()
      ..moveTo(42, 28)
      ..lineTo(47, 28)
      ..arcToPoint(const Offset(47, 42), radius: const Radius.circular(7))
      ..lineTo(42, 42),
    _stroke(0xFFC06A45, 4)..strokeCap = StrokeCap.butt,
  );
}

void _cat(Canvas canvas) {
  canvas.drawPath(
    Path()
      ..moveTo(12, 50)
      ..quadraticBezierTo(5, 47, 8, 38),
    _stroke(0xFF9C8268, 4.5),
  );
  _oval(canvas, 30, 45, 17, 13, 0xFF9C8268); // body
  canvas.drawCircle(const Offset(45, 28), 10.5, _fill(0xFF9C8268)); // head
  _polygon(canvas, const [Offset(38, 22), Offset(40, 13), Offset(46, 19)],
      0xFF9C8268);
  _polygon(canvas, const [Offset(52, 22), Offset(50, 13), Offset(44, 19)],
      0xFF9C8268);
  canvas.drawCircle(const Offset(42, 28), 1.4, _fill(0xFFF2E8D2));
  canvas.drawCircle(const Offset(49, 28), 1.4, _fill(0xFFF2E8D2));
}

void _houses(Canvas canvas) {
  _rrect(canvas, 8, 30, 22, 28, 2, 0xFFC98977);
  _polygon(canvas, const [Offset(5, 32), Offset(19, 17), Offset(33, 32)],
      0xFF9C6B5A);
  _rrect(canvas, 36, 22, 24, 36, 2, 0xFFD9B97A);
  _polygon(canvas, const [Offset(33, 24), Offset(48, 9), Offset(63, 24)],
      0xFFB08A3E);
  _rrect(canvas, 66, 34, 22, 24, 2, 0xFF8FA8A0);
  _polygon(canvas, const [Offset(63, 36), Offset(77, 22), Offset(91, 36)],
      0xFF5E7A72);
  _rrect(canvas, 16, 44, 7, 14, 1.5, 0xFFF2E8D2); // windows
  _rrect(canvas, 45, 32, 7, 8, 1.5, 0xFFF2E8D2);
  _rrect(canvas, 73, 42, 7, 7, 1.5, 0xFFF2E8D2);
}

void _palette(Canvas canvas) {
  canvas.drawPath(
    Path()
      ..moveTo(32, 8)
      ..cubicTo(46, 8, 56, 17, 56, 28)
      ..cubicTo(56, 35, 51, 38, 45, 38)
      ..lineTo(38, 38)
      ..cubicTo(34, 38, 32, 41, 34, 45)
      ..cubicTo(36, 50, 32, 56, 25, 56)
      ..cubicTo(15, 56, 8, 45, 8, 32)
      ..cubicTo(8, 18, 19, 8, 32, 8)
      ..close(),
    _fill(0xFFD9C9A8),
  );
  canvas.drawCircle(const Offset(21, 40), 4, _fill(0xFFF2E8D2)); // thumb hole
  canvas.drawCircle(const Offset(22, 22), 3.6, _fill(0xFFC06A45));
  canvas.drawCircle(const Offset(33, 17), 3.6, _fill(0xFF7B8456));
  canvas.drawCircle(const Offset(44, 22), 3.6, _fill(0xFFD9A33F));
  canvas.drawCircle(const Offset(45, 32), 3.6, _fill(0xFFD79B86));
  canvas.drawLine(
    const Offset(46, 46),
    const Offset(58, 57),
    _stroke(0xFF8A6B43, 4),
  ); // brush
}

void _sprout(Canvas canvas) {
  // The growing stem ("continue-progress" costume): a young shoot with two
  // leaves, not yet blooming — work in progress.
  canvas.drawPath(
    Path()
      ..moveTo(24, 44)
      ..quadraticBezierTo(27, 32, 23, 16),
    _stroke(0xFF7B8456, 3),
  );
  _oval(canvas, 17, 27, 7, 3.6, 0xFF86935F, rotationDegrees: -32);
  _oval(canvas, 31, 20, 7, 3.6, 0xFF6F7E4E, rotationDegrees: 28);
  _pot(canvas);
}

void _sprig(Canvas canvas) {
  // Potted sunflower under the completion plaque: stem, head, pot.
  canvas.drawLine(
    const Offset(24, 32),
    const Offset(24, 52),
    _stroke(0xFF7B8456, 3)..strokeCap = StrokeCap.butt,
  );
  canvas.save();
  canvas.translate(7, 1);
  canvas.scale(34 / 64);
  _sunflower(canvas);
  canvas.restore();
  canvas.save();
  canvas.translate(9, 30);
  canvas.scale(30 / 48, 40 / 64);
  _pot(canvas);
  canvas.restore();
}
