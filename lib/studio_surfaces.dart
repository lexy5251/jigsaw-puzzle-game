// The painted material of the Studio look (docs/design/brushwork-mockup.html,
// treatment E): cards are "daubs of paint" with slightly uneven corners and a
// soft shadow, and artwork always sits in a frame with a light mat ring.
// The mockup gets the wobble from an SVG turbulence filter; the Flutter
// translation is elliptical, per-corner radii — cheap and deterministic.

import 'package:flutter/material.dart';

import 'studio_theme.dart';

/// Preset corner silhouettes. Each corner is a different ellipse so no card
/// edge reads as machine-perfect; neighboring cards should use different
/// presets (see [PaintedCard.variant]).
const List<BorderRadius> _wobbles = [
  BorderRadius.only(
    topLeft: Radius.elliptical(22, 18),
    topRight: Radius.elliptical(17, 23),
    bottomLeft: Radius.elliptical(19, 24),
    bottomRight: Radius.elliptical(24, 17),
  ),
  BorderRadius.only(
    topLeft: Radius.elliptical(18, 24),
    topRight: Radius.elliptical(23, 17),
    bottomLeft: Radius.elliptical(24, 18),
    bottomRight: Radius.elliptical(17, 22),
  ),
  BorderRadius.only(
    topLeft: Radius.elliptical(24, 19),
    topRight: Radius.elliptical(18, 22),
    bottomLeft: Radius.elliptical(17, 23),
    bottomRight: Radius.elliptical(22, 18),
  ),
  BorderRadius.only(
    topLeft: Radius.elliptical(17, 22),
    topRight: Radius.elliptical(24, 18),
    bottomLeft: Radius.elliptical(22, 17),
    bottomRight: Radius.elliptical(18, 24),
  ),
];

/// A card painted as a single daub: organic corners, soft warm shadow,
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

  /// Picks one of the corner presets. Pass a grid/list index so adjacent
  /// cards get different silhouettes.
  final int variant;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = _wobbles[variant % _wobbles.length];
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: [shadow]),
      child: Material(
        color: color ?? Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Artwork in its frame: rounded clip plus the light mat ring painted over
/// the picture's edge ("artwork always sits in a painted frame with a
/// cream mat"). Wrap the image (or an image-filling Stack) in this.
class FramedArt extends StatelessWidget {
  const FramedArt({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(13);
    return Container(
      // Foreground, not decoration: the mat must overlap the artwork.
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: StudioColors.matRing, width: 3),
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

/// A small organic-edged dot of accent paint (category swatches).
class PaintedSwatch extends StatelessWidget {
  const PaintedSwatch({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.elliptical(7, 6),
          topRight: Radius.elliptical(6, 8),
          bottomLeft: Radius.elliptical(6, 7),
          bottomRight: Radius.elliptical(8, 6),
        ),
      ),
    );
  }
}
