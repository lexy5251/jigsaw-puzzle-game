// The puzzle-piece status family (owner's v21 pick A): done, ongoing and
// streak all speak in the app's own object. One shape — riso_icons'
// familyPiecePath — so the nav icon, the done sticker, the % pill, the
// category meter and the home streak can never drift apart.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'riso_icons.dart';
import 'studio_theme.dart';

/// The category header's progress line; shared with tests.
String pieceMeterText(int done, int total) => '$done of $total pieced together';

/// One family piece, painted. The building block of every marker.
class FamilyPiece extends StatelessWidget {
  const FamilyPiece({
    super.key,
    required this.size,
    this.fill,
    this.stroke,
    this.strokeWidth = 3,
    this.outline,
    this.rotationDegrees = 0,
  });

  final double size;

  /// Solid ink; null paints no fill.
  final Color? fill;

  /// Stroked ink; null paints no stroke.
  final Color? stroke;
  final double strokeWidth;

  /// A contrasting rim around a filled piece (the done sticker's cream
  /// edge); drawn outside the fill.
  final Color? outline;

  final double rotationDegrees;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FamilyPiecePainter(
        fill: fill,
        stroke: stroke,
        strokeWidth: strokeWidth,
        outline: outline,
        rotationDegrees: rotationDegrees,
      ),
    );
  }
}

class _FamilyPiecePainter extends CustomPainter {
  const _FamilyPiecePainter({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.outline,
    required this.rotationDegrees,
  });

  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
  final Color? outline;
  final double rotationDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.shortestSide / 48);
    if (rotationDegrees != 0) {
      canvas
        ..translate(24, 24)
        ..rotate(rotationDegrees * math.pi / 180)
        ..translate(-24, -24);
    }
    final path = familyPiecePath();
    if (outline case final rim?) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 2
          ..strokeJoin = StrokeJoin.round
          ..color = rim,
      );
    }
    if (fill case final ink?) {
      canvas.drawPath(path, Paint()..color = ink);
    }
    if (stroke case final ink?) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FamilyPiecePainter old) =>
      old.fill != fill ||
      old.stroke != stroke ||
      old.strokeWidth != strokeWidth ||
      old.outline != outline ||
      old.rotationDegrees != rotationDegrees;
}

/// "Done" — the last piece, clicked in: a tomato piece sticker with a cream
/// rim and the structure-dark print shadow, tilted like it was slapped on.
/// Sits on a card's top-right corner, hanging slightly over the edge.
class DonePieceSticker extends StatelessWidget {
  const DonePieceSticker({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Own node: without it the label merges into the card's
      // title-labelled node and completed state goes silent for a11y/e2e.
      container: true,
      label: statusCompletedLabel,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _StickerShadowPainter(),
          child: const FamilyPiece(
            size: 44,
            fill: StudioColors.tomato,
            outline: StudioColors.card,
            strokeWidth: 1.4,
            rotationDegrees: 8,
          ),
        ),
      ),
    );
  }
}

/// The sticker's hard offset shadow, in structure-dark — painted as a
/// second, displaced copy of the same piece under the sticker.
class _StickerShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(2.5, 3)
      ..scale(size.shortestSide / 48)
      ..translate(24, 24)
      ..rotate(8 * math.pi / 180)
      ..translate(-24, -24)
      ..drawPath(
        familyPiecePath(),
        Paint()..color = StudioColors.structureDark,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "Ongoing" — a cream pill with an open (stroked) piece and the percent,
/// both in tomato; structure-ink border and mini offset shadow. Sits on a
/// card's bottom-right corner, inside the photo.
class ProgressPiecePill extends StatelessWidget {
  const ProgressPiecePill({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: statusInProgressLabel,
      value: '$percent%',
      // The visual % must not merge into the label (e2e matches it exactly).
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
        decoration: const BoxDecoration(
          color: StudioColors.card,
          borderRadius: BorderRadius.all(Radius.circular(999)),
          border: Border.fromBorderSide(
            BorderSide(color: StudioColors.structureInk, width: 2),
          ),
          boxShadow: [
            BoxShadow(
              color: StudioColors.structureInk,
              offset: Offset(2.5, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FamilyPiece(
              size: 15,
              stroke: StudioColors.tomato,
              strokeWidth: 5,
            ),
            const SizedBox(width: 4),
            Text(
              '$percent%',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: StudioColors.tomato,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The category header's meter: "N of M pieced together" with one mini
/// piece per painting filling tomato as the collection completes.
class PieceMeter extends StatelessWidget {
  const PieceMeter({super.key, required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: pieceMeterText(done, total),
      excludeSemantics: true,
      // Wrap, not Row: at accessibility text scales the line and the
      // pieces stack instead of overflowing the page's width.
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            pieceMeterText(done, total),
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: StudioColors.mutedInk,
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < total; i++)
                i < done
                    ? const FamilyPiece(size: 13, fill: StudioColors.tomato)
                    : const FamilyPiece(
                        size: 13,
                        stroke: StudioColors.structureInk,
                        strokeWidth: 4,
                      ),
            ],
          ),
        ],
      ),
    );
  }
}
