// The painted material of the Studio look (docs/design/brushwork-mockup.html,
// treatment E): cards are "daubs of paint" with torn-paper edges and a soft
// shadow, and artwork sits in a frame whose light mat ring tears the same
// way. The mockup gets the tear from an SVG turbulence filter; the Flutter
// translation is a seeded sine wave along the outline — cheap and
// deterministic (owner ruling UI-5: wavy edges on cards AND photo frames).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'studio_theme.dart';

/// Wave strength shared by every painted card; photo frames use the
/// gentler pair. One knob each so a global retune stays a one-line change
/// (private: every retune site is in this file).
const double _cardEdgeAmplitude = 4.0;
const double _cardEdgeWavelength = 78.0;
const double _frameEdgeAmplitude = 2.2;
const double _frameEdgeWavelength = 40.0;

/// A rounded-rect outline whose edge undulates like torn paper.
///
/// The wave is two sines with integer cycle counts over the outline's
/// length (so the path closes without a seam) and phases driven by [seed]
/// — pure trig, stable across rebuilds, so a card never shimmers.
class TornPaperBorder extends ShapeBorder {
  const TornPaperBorder({
    required this.seed,
    this.amplitude = _cardEdgeAmplitude,
    this.wavelength = _cardEdgeWavelength,
    this.cornerRadius = 22,
    this.ringColor,
    this.ringWidth = 3,
  });

  /// Varies the wave phases so neighboring cards tear differently.
  final int seed;

  final double amplitude;
  final double wavelength;
  final double cornerRadius;

  /// When set, [paint] strokes the torn outline just inside the edge —
  /// the photo frames' mat ring. Null paints nothing (cards get their
  /// edge from the fill alone).
  final Color? ringColor;
  final double ringWidth;

  /// The ring is the only inset this border owns; without one, inner
  /// and outer edges coincide.
  double get _ringInset => ringColor == null ? 0 : ringWidth;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(_ringInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(_ringInset), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    // Degenerate rects happen in real paints: ShapeDecoration's shadow
    // pre-pass deflates by negative spread, which can collapse or invert
    // a tiny card's rect. Bail out before metrics (empty iterator) and
    // Radius.circular (negative assert) can throw.
    if (rect.isEmpty) {
      return Path()..addRect(rect);
    }
    // Small tiles get proportionally gentler waves instead of noise.
    final shortSide = math.min(rect.width, rect.height);
    final amp = math.min(amplitude, shortSide / 28);
    final radius = math.min(cornerRadius, shortSide / 4);
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final metric = base.computeMetrics().first;
    final length = metric.length;
    if (length < wavelength * 2 || amp <= 0) {
      return base;
    }
    // Integer cycle counts make every component periodic over the
    // outline, so the displaced path meets itself exactly where it
    // started. Three mixed frequencies plus a slow amplitude swell keep
    // the tear irregular — a single sine reads as postage-stamp scallops.
    final n0 = math.max(2, (length / (wavelength * 3.1)).round());
    final n1 = math.max(3, (length / wavelength).round());
    final n2 = math.max(5, (length / (wavelength * 0.42)).round());
    final n3 = math.max(8, (length / (wavelength * 0.18)).round());
    final p0 = seed * 1.9 + 0.8;
    final p1 = seed * 2.4;
    final p2 = seed * 5.3 + 1.7;
    final p3 = seed * 3.7 + 4.2;
    final torn = Path();
    final samples = math.max(24, (length / 3.5).ceil());
    for (var i = 0; i < samples; i++) {
      final d = i * length / samples;
      final tangent = metric.getTangentForOffset(d)!;
      final phase = d / length * 2 * math.pi;
      final ripple =
          0.52 * math.sin(n1 * phase + p1) +
          0.33 * math.sin(n2 * phase + p2) +
          0.15 * math.sin(n3 * phase + p3);
      final swell = 0.7 + 0.3 * math.sin(n0 * phase + p0);
      final wave = amp * swell * ripple;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final point = tangent.position + normal * wave;
      if (i == 0) {
        torn.moveTo(point.dx, point.dy);
      } else {
        torn.lineTo(point.dx, point.dy);
      }
    }
    return torn..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final ring = ringColor;
    if (ring == null) {
      return;
    }
    // One path for clip and stroke keeps the ring exactly parallel to
    // the torn edge: stroke it double-width centered on the edge, clipped
    // to the shape, so [ringWidth] of it shows inside — like the old
    // inward-painting Border.all.
    final edge = getOuterPath(rect, textDirection: textDirection);
    canvas
      ..save()
      ..clipPath(edge)
      ..drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth * 2
          ..color = ring,
      )
      ..restore();
  }

  @override
  ShapeBorder scale(double t) => TornPaperBorder(
    seed: seed,
    amplitude: amplitude * t,
    // A length along the outline, so a scaled copy scales it too.
    wavelength: wavelength * t,
    cornerRadius: cornerRadius * t,
    ringColor: ringColor,
    ringWidth: ringWidth * t,
  );

  // Value equality matters here: PaintedCard builds a fresh border per
  // rebuild, and without it Material restarts its shape tween, the
  // clipper reclips, and ShapeDecoration re-tears its paths every build.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TornPaperBorder &&
        other.seed == seed &&
        other.amplitude == amplitude &&
        other.wavelength == wavelength &&
        other.cornerRadius == cornerRadius &&
        other.ringColor == ringColor &&
        other.ringWidth == ringWidth;
  }

  @override
  int get hashCode => Object.hash(
    seed,
    amplitude,
    wavelength,
    cornerRadius,
    ringColor,
    ringWidth,
  );
}

/// A card painted as a single daub: torn-paper edge, soft warm shadow,
/// linen fill by default. Replaces [Card] on Studio screens.
class PaintedCard extends StatelessWidget {
  const PaintedCard({
    super.key,
    this.color,
    this.variant = 0,
    this.onTap,
    this.padding,
    this.shadow = softShadow,
    required this.child,
  });

  /// Mockup: 0 3px 10px -5px rgba(40,25,10,.35) — warm, not gray.
  static const softShadow = BoxShadow(
    color: StudioColors.cardShadow,
    offset: Offset(0, 3),
    blurRadius: 10,
    spreadRadius: -5,
  );

  /// A touch deeper, for cards whose fill matches the wallpaper and whose
  /// edge therefore only exists as shadow (the category cards).
  static const groundShadow = BoxShadow(
    color: StudioColors.cardShadow,
    offset: Offset(0, 4),
    blurRadius: 14,
    spreadRadius: -3,
  );

  /// Fill color; defaults to the theme's linen surface. Ground variants
  /// (blush, moss) come from `StudioColors`.
  final Color? color;

  /// The card's drop shadow; [softShadow] unless the context needs more.
  final BoxShadow shadow;

  /// Seeds the tear so adjacent cards get different silhouettes. Pass a
  /// grid/list index.
  final int variant;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = TornPaperBorder(seed: variant);
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: [shadow]),
      child: Material(
        color: color ?? Theme.of(context).colorScheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Artwork in its frame: torn-edged clip plus the light mat ring painted
/// over the picture's edge ("artwork always sits in a painted frame with
/// a cream mat"). Wrap the image (or an image-filling Stack) in this.
class FramedArt extends StatelessWidget {
  const FramedArt({super.key, this.seed = 1, required this.child});

  /// Varies the frame's tear; grids pass their item index so a wall of
  /// equal-sized frames doesn't repeat one identical outline.
  final int seed;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = TornPaperBorder(
      seed: seed,
      amplitude: _frameEdgeAmplitude,
      wavelength: _frameEdgeWavelength,
      cornerRadius: 13,
      ringColor: StudioColors.matRing,
    );
    return Container(
      // Foreground, not decoration: the mat must overlap the artwork.
      foregroundDecoration: ShapeDecoration(shape: shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: child,
      ),
    );
  }
}

/// The photo grids' shared geometry (2 across on phones — UI-6 ruling):
/// category pages and My Puzzles must render identically, so both read
/// this one spec.
const photoGridPadding = EdgeInsets.all(16);
const photoGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 200,
  mainAxisSpacing: 12,
  crossAxisSpacing: 12,
  // The catalog photos are square (1:1), so square cells crop nothing.
  childAspectRatio: 1.0,
);

/// A catalog photo as a bare, hand-placed card: straight rounded edges, a
/// hair's-width alternating tilt, and no visible title — the UI-6 ruling
/// for photo grids (names live on in the semantics label). Shared by the
/// category pages and My Puzzles so the two grids cannot drift apart.
class TiltedPhotoCard extends StatelessWidget {
  const TiltedPhotoCard({
    super.key,
    required this.assetPath,
    required this.title,
    required this.semanticsIdentifier,
    required this.variant,
    required this.onTap,
    this.overlays = const [],
  });

  /// Corner rounding of the photo card (owner's UI-6 round-2 pick:
  /// style C at a smaller radius than the sheet's 18).
  static const cornerRadius = Radius.circular(12);

  /// Decode width for every photo thumbnail surface. The ImageCache keys
  /// on this value, so all surfaces (and the preview harnesses' warm-up)
  /// must share it or the same photo decodes twice.
  static const thumbnailCacheWidth = 640;

  /// Alternating hair's-width tilt, in radians: hand-placed, not torn —
  /// straight edges are the UI-6 ruling for bare images.
  static double tiltFor(int variant) =>
      (variant.isEven ? -0.9 : 0.8) * math.pi / 180;

  final String assetPath;

  /// Screen-reader name and decode-failure fallback; never painted.
  final String title;

  /// Lets e2e tests tap one specific photo without matching its title.
  final String semanticsIdentifier;

  /// Grid item index: drives the alternating tilt direction.
  final int variant;

  final VoidCallback onTap;

  /// Stacked over the photo, under the tap ripple (badges, count chips).
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticsIdentifier,
      label: title,
      button: true,
      child: Transform.rotate(
        angle: tiltFor(variant),
        child: Container(
          decoration: const BoxDecoration(
            // Opaque surface so the tile reads as a card while the photo is
            // still decoding (or if it ever fails), not a floating shadow.
            color: StudioColors.card,
            borderRadius: BorderRadius.all(cornerRadius),
            boxShadow: [PaintedCard.groundShadow],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(cornerRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  assetPath,
                  fit: BoxFit.cover,
                  // Decode smaller previews to reduce memory use.
                  cacheWidth: thumbnailCacheWidth,
                  // A photo that fails to decode would otherwise leave an
                  // anonymous blank card — fall back to the visible title.
                  errorBuilder: (context, _, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                ...overlays,
                // Above the photo so the tap ripple shows on it.
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: onTap),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small organic-edged dot of accent paint (category swatches).
class PaintedSwatch extends StatelessWidget {
  const PaintedSwatch({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    // The elliptical radii scale with the size so a larger daub keeps the
    // same organic silhouette instead of looking rounder.
    final unit = size / 14;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: Radius.elliptical(7 * unit, 6 * unit),
          topRight: Radius.elliptical(6 * unit, 8 * unit),
          bottomLeft: Radius.elliptical(6 * unit, 7 * unit),
          bottomRight: Radius.elliptical(8 * unit, 6 * unit),
        ),
      ),
    );
  }
}
